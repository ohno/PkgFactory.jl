const WA = PkgFactory.WebAPI
const WU = PkgFactory.WebUI
webjson(status, value) = WA.HTTP.Response(status, WA.JSON3.write(value))
webpost(path, body; token="test-token") = WA.HTTP.Request("POST", path,
    ["Content-Type" => "application/json", "Authorization" => "Bearer $token"], WA.JSON3.write(body))

@testset "Public Web UI validation and error boundaries" begin
    policy = WU.WebPolicy(public_origin="https://packages.example")
    rejected = (args...; kwargs...) -> error("Network must not be called")
    config = Dict("owner" => "ohno", "package_name" => "MyPackage", "authors" => ["Alice"], "description" => "Example")
    for (key, value) in [("owner", "../elsewhere?x=1"), ("authors", [42]),
        ("authors", fill("Alice", 21)), ("resume", 1), ("description", repeat("a", 2001)), ("extra", "unknown")]
        req = webpost("/api/packages", merge(config, Dict(key => value)))
        result = WU.handle_request(req; policy=WU.WebPolicy(), requester=rejected)
        @test result.status == 400
    end
    req = webpost("/api/oauth/device", Dict())
    push!(req.headers, "Origin" => "https://attacker.example")
    @test WU.handle_request(req; policy, requester=rejected).status == 403
    @test WU.handle_request(WA.HTTP.Request("POST", "/api/oauth/device", [], "{}"); requester=rejected).status == 415
    @test WU.handle_request(webpost("/api/oauth/device", Dict("x" => repeat("a", 70000))); requester=rejected).status == 413
    req = WA.HTTP.Request("GET", "/api/github/owners", ["Authorization" => "Bearer top-secret"])
    result = WU.handle_request(req; requester=(args...; kwargs...) -> error("top-secret backend details"))
    @test result.status == 503
    @test !occursin("top-secret", String(result.body))
    @test WU._error_response(ErrorException("private-key-material")).status == 500
    @test !occursin("private-key-material", String(WU._error_response(ErrorException("private-key-material")).body))
    root = WU.handle_request(WA.HTTP.Request("GET", "/"))
    @test occursin("frame-ancestors 'none'", WA.HTTP.header(root, "Content-Security-Policy"))
    @test WA.HTTP.header(root, "X-Frame-Options") == "DENY"
end

@testset "Bounded transport and encoded OAuth parameters" begin
    options = Ref{Any}()
    transport = WA.GitHubTransport(request=(args...; kwargs...) -> (options[] = kwargs; webjson(200, Dict())),
        connect_timeout=2, read_timeout=3)
    transport("POST", "https://api.github.com/example"; status_exception=false)
    @test options[][:connect_timeout] == 2
    @test options[][:readtimeout] == 3
    @test options[][:retry] === false
    @test options[][:redirect] === false
    payload = Ref("")
    WA.device_flow_poll("code&client_id=evil", "expected";
        requester=(args...; body, kwargs...) -> (payload[] = body; webjson(200, Dict())))
    @test occursin("code%26client_id%3Devil", payload[])
    @test !occursin("&client_id=evil", payload[])
    @test_throws InterruptException WA._request_json("GET", "https://api.github.com/user";
        requester=(args...; kwargs...) -> throw(InterruptException()))
end

@testset "OAuth rate limits expire without retaining credentials" begin
    clock = Ref(0.0)
    policy = WU.WebPolicy(clock=() -> clock[])
    calls = Ref(0)
    requester = (args...; kwargs...) -> (calls[] += 1; webjson(200, Dict("user_code" => "ABC")))
    for _ in 1:6
        @test WU.handle_request(webpost("/api/oauth/device", Dict()); policy, client_ip="a", requester).status == 200
    end
    response = WU.handle_request(webpost("/api/oauth/device", Dict()); policy, client_ip="a", requester)
    @test response.status == 429
    @test WA.HTTP.header(response, "Retry-After") == "60"
    @test calls[] == 6
    @test WU.handle_request(webpost("/api/oauth/device", Dict()); policy, client_ip="b", requester).status == 200
    clock[] = 61
    @test WU.handle_request(webpost("/api/oauth/device", Dict()); policy, client_ip="a", requester).status == 200
end

@testset "Repository exclusion is concurrent and released on failure" begin
    entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
    task = @async WA._with_repository_lock("ohno", "MyPackage.jl") do
        put!(entered, nothing)
        take!(release)
    end
    take!(entered)
    @test_throws WA.GitHubAPIError WA._with_repository_lock(() -> nothing, "OHNO", "mypackage.jl")
    @test WA._with_repository_lock(() -> :other, "another", "MyPackage.jl") == :other
    put!(release, nothing)
    wait(task)
    @test_throws ErrorException WA._with_repository_lock(() -> error("failure"), "ohno", "MyPackage.jl")
    @test WA._with_repository_lock(() -> :released, "ohno", "MyPackage.jl") == :released
end

@testset "Concurrent real key generation preserves working directory" begin
    original = pwd()
    first_task = @async WA._generate_keys()
    second_task = @async WA._generate_keys()
    a, b = fetch(first_task), fetch(second_task)
    @test pwd() == original
    @test a[1] != b[1]
    @test all(pair -> startswith(pair[1], "ssh-rsa "), [a, b])
    @test all(pair -> occursin("PRIVATE KEY", String(WA.Base64.base64decode(pair[2]))), [a, b])
    @test !isfile("github-private-key")
    for pair in [a, b]
        mktempdir() do directory
            file = joinpath(directory, "key")
            write(file, WA.Base64.base64decode(pair[2]))
            if Sys.iswindows()
                owner = strip(read(`whoami`, String))
                grant = owner * ":(F)"
                run(pipeline(`icacls $file /inheritance:r /grant:r $grant`; stdout=devnull))
            else
                chmod(file, 0o600)
            end
            derived = read(`ssh-keygen -y -f $file`, String)
            @test split(derived)[2] == split(pair[1])[2]
        end
    end
end

# In-memory GitHub state with actual template generation and secret encryption.
function github_fixture()
    state = Dict{String,Any}("exists" => false, "files" => Dict{String,String}(),
        "pending" => Dict{String,String}(), "keys" => Any[], "secret" => false,
        "fail_secret" => false, "next_id" => 0, "writes" => 0)
    requester = function(method, url; body="", kwargs...)
        data = isempty(body) ? Dict{String,Any}() : WA.JSON3.read(body, Dict{String,Any})
        method == "GET" || (state["writes"] += 1)
        if endswith(url, "/user")
            return webjson(200, Dict("login" => "ohno"))
        elseif endswith(url, "/repos/ohno/MyPackage.jl")
            return webjson(state["exists"] ? 200 : 404, Dict("default_branch" => "main"))
        elseif endswith(url, "/user/repos")
            state["exists"] = true
            return webjson(201, Dict("default_branch" => "main"))
        elseif occursin("/contents/", url)
            path = split(url, "/contents/")[2]
            if method == "PUT"
                state["files"][path] = String(WA.Base64.base64decode(data["content"]))
                return webjson(200, Dict())
            end
            haskey(state["files"], path) || return webjson(404, Dict())
            return webjson(200, Dict("sha" => "file-sha", "content" => WA.Base64.base64encode(state["files"][path])))
        elseif endswith(url, "/git/ref/heads/main") || endswith(url, "/git/ref/heads/gh-pages")
            return webjson(200, Dict("object" => Dict("sha" => "head")))
        elseif endswith(url, "/git/commits/head")
            return webjson(200, Dict("tree" => Dict("sha" => "tree")))
        elseif endswith(url, "/git/trees")
            state["pending"] = Dict(entry["path"] => entry["content"] for entry in data["tree"])
            return webjson(201, Dict("sha" => "new-tree"))
        elseif endswith(url, "/git/commits")
            return webjson(201, Dict("sha" => "new-commit"))
        elseif endswith(url, "/git/refs/heads/main")
            merge!(state["files"], state["pending"])
            return webjson(200, Dict())
        elseif occursin("/keys?", url)
            return webjson(200, state["keys"])
        elseif method == "POST" && endswith(url, "/keys")
            state["next_id"] += 1
            key = merge(data, Dict("id" => state["next_id"]))
            push!(state["keys"], key)
            return webjson(201, key)
        elseif method == "DELETE" && occursin("/keys/", url)
            id = parse(Int, last(split(url, '/')))
            filter!(key -> key["id"] != id, state["keys"])
            return WA.HTTP.Response(204)
        elseif endswith(url, "/actions/secrets/public-key")
            return webjson(200, Dict("key" => WA.Base64.base64encode(zeros(UInt8, 32)), "key_id" => "key-id"))
        elseif endswith(url, "/actions/secrets/DOCUMENTER_KEY")
            state["fail_secret"] && return webjson(503, Dict("message" => "failure"))
            state["secret"] = true
            return WA.HTTP.Response(204)
        end
        error("Unexpected fixture request: $method $url")
    end
    return state, requester
end

@testset "GitHub partial failure, recovery and unrelated repositories" begin
    state, requester = github_fixture()
    args = ("token", "ohno", "MyPackage", ["Alice"], "Example")
    key_generator = () -> ("ssh-rsa example-$(state["next_id"])", "private-material")
    state["fail_secret"] = true
    err = try
        WA.create_package(args...; requester, key_generator)
        nothing
    catch err
        err
    end
    @test err isa WA.CreationError
    @test err.stage == "documentation"
    @test !occursin("private-material", sprint(showerror, err))
    @test WA.repository_status("token", "ohno", "MyPackage"; requester)["state"] == "files_committed"
    @test length(state["keys"]) == 1
    state["fail_secret"] = false
    result = WA.create_package(args...; requester, key_generator, resume=true)
    @test result["resumed"]
    @test state["secret"]
    @test length(state["keys"]) == 1
    @test state["keys"][1]["id"] == 2
    @test WA.repository_status("token", "ohno", "MyPackage"; requester)["state"] == "complete"
    writes = state["writes"]
    WA.create_package(args...; requester, key_generator, resume=true)
    @test state["writes"] == writes
    @test_throws WA.InputError WA.create_package(args...; requester, resume=true, template_name="minimum")
    state["files"]["Project.toml"] *= "\n# edited"
    @test_throws WA.InputError WA.create_package(args...; requester, resume=true)
    @test state["writes"] == writes
    empty!(state["files"])
    @test WA.repository_status("token", "ohno", "MyPackage"; requester)["state"] == "unverified"
    @test_throws WA.InputError WA.create_package(args...; requester, resume=true)
    @test state["writes"] == writes
end

@testset "Real HTTP limits and caller isolation" begin
    sockets = WU.Sockets
    listener = sockets.listen(sockets.IPv4("127.0.0.1"), 0)
    port = Int(sockets.getsockname(listener)[2])
    close(listener)
    requester = function(method, url; headers, kwargs...)
        token = only(filter(h -> first(h) == "Authorization", headers))[2]
        login = replace(token, "Bearer " => "")
        return webjson(200, endswith(url, "/user") ? Dict("login" => login, "name" => login) : Any[])
    end
    server = WU.start("127.0.0.1", port; max_body_bytes=64, requester)
    try
        url = "http://127.0.0.1:$port"
        tasks = map(["alice", "bob"]) do login
            @async WA.HTTP.get(url * "/api/github/owners", ["Authorization" => "Bearer $login"]; readtimeout=10)
        end
        for (login, task) in zip(["alice", "bob"], tasks)
            @test WA.JSON3.read(String(fetch(task).body))["owners"][1]["login"] == login
        end
        oversized = WA.HTTP.post(url * "/api/oauth/device", ["Content-Type" => "application/json"], repeat("x", 65);
            status_exception=false, readtimeout=10)
        @test oversized.status == 413
        # No Content-Length: enforce the limit while consuming chunked bodies.
        sock = sockets.connect(sockets.IPv4("127.0.0.1"), port)
        try
            write(sock, "POST /api/oauth/device HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n41\r\n" * repeat("x", 65) * "\r\n0\r\n\r\n")
            @test occursin("413", readline(sock))
        finally
            close(sock)
        end
        origin = WA.HTTP.post(url * "/api/oauth/device",
            ["Content-Type" => "application/json", "Origin" => "https://other.example"], "{}";
            status_exception=false, readtimeout=10)
        @test origin.status == 403
    finally
        close(server)
    end
end

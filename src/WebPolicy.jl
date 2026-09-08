# Included inside WebUI. One policy per serving process; never store raw tokens.
struct RequestError <: Exception
    status::Int
    message::String
end

mutable struct WebPolicy
    buckets::Dict{Tuple{String,String},Tuple{Float64,Int}}
    mutex::ReentrantLock
    clock::Function
    public_origin::String
    max_body_bytes::Int
end
function WebPolicy(; public_origin="", max_body_bytes=65536, clock=() -> time_ns() / 1e9)
    max_body_bytes > 0 || throw(ArgumentError("max_body_bytes must be positive"))
    WebPolicy(Dict{Tuple{String,String},Tuple{Float64,Int}}(), ReentrantLock(), clock,
        rstrip(String(public_origin), '/'), max_body_bytes)
end
const DEFAULT_POLICY = WebPolicy()

function _rate_limit!(policy, key, category, limit)
    lock(policy.mutex) do
        now = policy.clock()
        filter!(pair -> now - pair.second[1] < 60, policy.buckets)
        bucket = (category, key)
        start, count = get(policy.buckets, bucket, (now, 0))
        (haskey(policy.buckets, bucket) || length(policy.buckets) < 4096) ||
            throw(RequestError(429, "Request capacity reached. Try again later."))
        count < limit || throw(RequestError(429, "Too many requests. Try again later."))
        policy.buckets[bucket] = (start, count + 1)
    end
end

function _guard_request(request, policy, client_ip)
    method, path = _route(request)
    startswith(path, "/api/") || return
    path == "/api/health" && return
    origin = HTTP.header(request, "Origin", "")
    isempty(origin) || origin == policy.public_origin || throw(RequestError(403, "Origin is not allowed."))
    _rate_limit!(policy, client_ip, "api", 120)
    if path == "/api/oauth/device"
        _rate_limit!(policy, client_ip, "oauth_start", 6)
    elseif path == "/api/oauth/token"
        _rate_limit!(policy, client_ip, "oauth_poll", 60)
    elseif path == "/api/packages"
        token = _access_token(request)
        _rate_limit!(policy, bytes2hex(WebAPI.SHA.sha256(token)), "create", 5)
    end
    if method == "POST"
        length(request.body) <= policy.max_body_bytes || throw(RequestError(413, "Request body is too large."))
        split(HTTP.header(request, "Content-Type", ""), ';')[1] == "application/json" ||
            throw(RequestError(415, "Content-Type must be application/json."))
    end
end

function _fields(body, allowed, required=String[])
    all(key -> key in allowed, keys(body)) || throw(WebAPI.InputError("Unknown field."))
    all(key -> haskey(body, key), required) || throw(WebAPI.InputError("Required field is missing."))
end

function _package_body(request)
    body = _json_body(request)
    _fields(body, ["owner", "package_name", "authors", "description", "codecov_token",
        "template", "visibility", "commit_message", "resume"], ["owner", "package_name", "authors", "description"])
    for (name, limit) in [("owner", 100), ("package_name", 100), ("description", 2000),
        ("codecov_token", 4096), ("template", 100), ("visibility", 10), ("commit_message", 500)]
        haskey(body, name) && WebAPI._bounded_text(body[name], name, limit; empty=name in ("description", "codecov_token"))
    end
    authors = body["authors"]
    authors isa AbstractVector && 1 <= length(authors) <= 20 || throw(WebAPI.InputError("authors must contain 1 to 20 names."))
    foreach(author -> WebAPI._bounded_text(author, "author", 200), authors)
    get(body, "resume", false) isa Bool || throw(WebAPI.InputError("resume must be a boolean."))
    body
end

function _error_response(err)
    err isa InterruptException && throw(err)
    if err isa RequestError
        response = _json_response(err.status, Dict("error" => err.message))
        err.status == 429 && push!(response.headers, "Retry-After" => "60")
        return response
    elseif err isa WebAPI.InputError
        return _json_response(400, Dict("error" => err.message))
    elseif err isa WebAPI.CreationError
        return _json_response(err.status, Dict("error" => sprint(showerror, err), "stage" => err.stage,
            "check_status" => true))
    elseif err isa WebAPI.GitHubAPIError
        # Do not reflect upstream response text, URLs or arbitrary exceptions.
        response = _json_response(err.status, Dict("error" => "GitHub request failed. Check authorization and repository status."))
        isnothing(err.retry_after) || push!(response.headers, "Retry-After" => string(clamp(err.retry_after, 1, 3600)))
        return response
    end
    return _json_response(500, Dict("error" => "An internal error occurred. Check repository status before retrying."))
end

function _serve_stream(stream, policy, handler, trusted_proxies)
    request = stream.message
    request_id = string(WebAPI.UUIDs.uuid4())
    started = time_ns()
    peer = string(first(Sockets.getpeername(stream)))
    # X-Real-IP is used only for an explicitly trusted immediate peer. That
    # proxy must overwrite the header and the backend must not be public.
    forwarded = HTTP.header(request, "X-Real-IP", "")
    client_ip = peer in trusted_proxies && 0 < ncodeunits(forwarded) <= 64 &&
        occursin(r"^[0-9a-fA-F:.]+$", forwarded) ? forwarded : peer
    response = try
        declared = tryparse(Int, HTTP.header(request, "Content-Length", "0"))
        isnothing(declared) || 0 <= declared <= policy.max_body_bytes ||
            throw(RequestError(413, "Request body is too large."))
        body = UInt8[]
        while !eof(stream)
            append!(body, read(stream, min(8192, policy.max_body_bytes + 1 - length(body))))
            length(body) <= policy.max_body_bytes || throw(RequestError(413, "Request body is too large."))
        end
        request.body = body
        HTTP.closeread(stream)
        handler(request; policy, client_ip)
    catch err
        _error_response(err)
    end
    method, path = _route(request)
    # HTTP.jl can include the Request in connection-error logs. Scrub it once
    # the handler is finished, including OAuth/device and Codecov request bodies.
    request.body = UInt8[]
    filter!(header -> lowercase(first(header)) in ("content-length", "transfer-encoding", "connection"), request.headers)
    request.target = "/redacted"
    request.response = response
    response.request = request
    HTTP.setheader(stream, "Connection" => "close")
    HTTP.setheader(stream, "X-Request-Id" => request_id)
    route = path in ("/", "/api/config", "/api/health", "/api/oauth/device", "/api/oauth/token",
        "/api/github/owners", "/api/github/repository-availability", "/api/github/repository-status", "/api/packages") ? path : "other"
    @info "PkgFactory request" request_id route status=response.status duration_ms=round(Int, (time_ns() - started) / 1e6)
    try
        HTTP.startwrite(stream)
        write(stream, response.body)
        HTTP.closewrite(stream)
    catch err
        err isa InterruptException && rethrow()
        @warn "PkgFactory response interrupted" request_id error_type=string(nameof(typeof(err)))
    finally
        close(stream) # Do not drain oversized bodies or leave a reusable connection.
    end
end

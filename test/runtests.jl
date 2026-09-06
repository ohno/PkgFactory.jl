using PkgFactory
using Test

mutable struct FakeCommandRunner
    commands::Vector{String}
    environments::Vector{Dict{String,String}}
    inputs::Vector{Union{Nothing,String}}
    authenticated::Bool
    repository_exists::Bool
    registered_package_names::Vector{String}
    project_file::Union{Nothing,String}
    main_branch_exists::Bool
    staged_changes::Bool
    gh_pages_exists::Bool
    deploy_key_exists::Bool
    documenter_secret_exists::Bool
end

mutable struct FakePackageCreator
    calls::Vector{Any}
    result::Bool
end

function (creator::FakePackageCreator)(args...; kwargs...)
    push!(creator.calls, (args = args, options = (; kwargs...)))
    return creator.result
end

function FakeCommandRunner(;
    authenticated::Bool = true,
    repository_exists::Bool = false,
    registered_package_names::Vector{String} = String[],
    project_file::Union{Nothing,String} = nothing,
    main_branch_exists::Union{Nothing,Bool} = nothing,
    staged_changes::Bool = true,
    gh_pages_exists::Bool = false,
    deploy_key_exists::Bool = false,
    documenter_secret_exists::Bool = false,
)
    return FakeCommandRunner(
        String[],
        Dict{String,String}[],
        Union{Nothing,String}[],
        authenticated,
        repository_exists,
        registered_package_names,
        project_file,
        isnothing(main_branch_exists) ? repository_exists : main_branch_exists,
        staged_changes,
        gh_pages_exists,
        deploy_key_exists,
        documenter_secret_exists,
    )
end

function (runner::FakeCommandRunner)(
    cmd::Cmd;
    env::Dict{String,String} = Dict{String,String}(),
    input::Union{Nothing,String} = nothing,
)
    command = string(cmd)
    push!(runner.commands, command)
    push!(runner.environments, env)
    push!(runner.inputs, input)

    if occursin("auth status", command)
        return runner.authenticated, "", runner.authenticated ? "" : "not authenticated"
    elseif occursin("api graphql", command)
        return true,
        """[{"data":{"viewer":{"login":"ohno","name":"Shuhei OHNO","organizations":{"nodes":[{"login":"AllowedOrg","name":"Allowed Org","viewerCanCreateRepositories":true},{"login":"DeniedOrg","name":"Denied Org","viewerCanCreateRepositories":false}]}}}}]""",
        ""
    elseif occursin("api user", command)
        return true, """{"login":"ohno","name":"Shuhei OHNO","id":59360244}""", ""
    elseif occursin("repo list", command)
        return true, "MyPkg.jl\nMyPkg1.jl\nMyPkg2.jl\n", ""
    elseif occursin("repos/JuliaRegistries/General/git/trees/", command)
        return true, join(runner.registered_package_names, '\n'), ""
    elseif occursin("contents/Project.toml", command)
        if isnothing(runner.project_file)
            return false, "", "HTTP 404: Not Found"
        end
        return true, PkgFactory.LocalAPI.Base64.base64encode(runner.project_file), ""
    elseif occursin("git/ref/heads/gh-pages", command)
        return runner.gh_pages_exists,
        "",
        runner.gh_pages_exists ? "" : "HTTP 404: Not Found"
    elseif occursin("git/ref/heads/main", command)
        if occursin("--silent", command)
            return runner.main_branch_exists,
            "",
            runner.main_branch_exists ? "" : "HTTP 404: Not Found"
        end
        return true, "abc123\n", ""
    elseif occursin("api repos/", command) && occursin("--silent", command)
        return runner.repository_exists,
        "",
        runner.repository_exists ? "" : "HTTP 404: Not Found"
    elseif occursin("diff --cached --quiet", command)
        return !runner.staged_changes, "", ""
    elseif occursin("secret list", command)
        secrets = runner.documenter_secret_exists ? "DOCUMENTER_KEY\n" : ""
        return true, secrets, ""
    elseif occursin("/keys --paginate", command)
        keys = runner.deploy_key_exists ? "Documenter\n" : ""
        return true, keys, ""
    end

    return true, "", ""
end

@testset "hello" begin
    @test occursin("Hello", PkgFactory.hello())
    @test occursin("Hello", PkgFactory.Verifications.hello())
    @test occursin("Hello", PkgFactory.Templates.hello())
    @test occursin("Hello", PkgFactory.LocalAPI.hello())
    @test occursin("Hello", PkgFactory.LocalUI.hello())
    @test occursin("Hello", PkgFactory.WebAPI.hello())
    @test occursin("Hello", PkgFactory.WebUI.hello())
end

@testset "notebook package workflow" begin
    config = PkgFactory.PackageConfig(
        owner = " ohno ",
        name = "MyPackage.jl",
        authors = [" Alice Smith "],
        description = " A package created from Jupyter ",
        template = "minimum",
    )
    @test config.owner == "ohno"
    @test config.name == "MyPackage"
    @test config.authors == ["Alice Smith"]
    @test config.description == "A package created from Jupyter"

    plan = PkgFactory.preview(config)
    @test plan.repository == "ohno/MyPackage.jl"
    @test "src/MyPackage.jl" in plan.files
    @test !any(occursin("PKG.jl"), plan.files)
    preview_text = sprint(show, MIME"text/plain"(), plan)
    @test occursin("https://github.com/ohno/MyPackage.jl", preview_text)
    @test occursin("No changes have been made", preview_text)

    @test_throws ErrorException PkgFactory.preview(PkgFactory.PackageConfig(
        owner = "ohno",
        name = "lowercase",
        authors = ["Alice Smith"],
        description = "Invalid package",
    ))
    @test_throws ErrorException PkgFactory.preview(PkgFactory.PackageConfig(
        owner = "ohno",
        name = "MyPackage",
        authors = ["Alice Smith"],
        description = "",
    ))

    backend = PkgFactory.GitHubAPI("notebook-secret-token")
    @test !occursin("notebook-secret-token", sprint(show, backend))
    @test occursin("redacted", sprint(show, backend))
    withenv("GITHUB_TOKEN" => "environment-token", "GH_TOKEN" => nothing) do
        @test PkgFactory.GitHubAPI().access_token == "environment-token"
    end

    creation_call = Ref{Any}()
    creator = function (args...; kwargs...)
        creation_call[] = (; args, options = (; kwargs...))
        return Dict(
            "repository" => "ohno/MyPackage.jl",
            "url" => "https://github.com/ohno/MyPackage.jl",
            "resumed" => false,
        )
    end
    result = PkgFactory.create!(
        plan;
        backend = backend,
        package_creator = creator,
    )
    @test result["repository"] == "ohno/MyPackage.jl"
    @test creation_call[].args[1] == "notebook-secret-token"
    @test creation_call[].args[2:6] == (
        "ohno",
        "MyPackage",
        ["Alice Smith"],
        "A package created from Jupyter",
        "",
    )
    @test creation_call[].options.template_name == "minimum"
    @test !creation_call[].options.resume
    direct_result = PkgFactory.create!(
        config;
        backend = backend,
        package_creator = creator,
    )
    @test direct_result["repository"] == "ohno/MyPackage.jl"
end

@testset "notebook GitHub device login" begin
    polls = Ref(0)
    requester = function (method, url; headers, body, status_exception)
        response = if endswith(url, "/device/code")
            Dict(
                "device_code" => "device-code",
                "user_code" => "ABCD-1234",
                "verification_uri" => "https://github.com/login/device",
                "expires_in" => 900,
                "interval" => 1,
            )
        else
            polls[] += 1
            polls[] == 1 ? Dict("error" => "authorization_pending") : Dict(
                "access_token" => "oauth-secret-token",
                "token_type" => "bearer",
                "scope" => "read:user,repo,workflow",
            )
        end
        return PkgFactory.WebAPI.HTTP.Response(
            200,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end
    delays = Int[]
    output = IOBuffer()
    backend = PkgFactory.github_device_login(
        requester = requester,
        sleeper = delay -> push!(delays, delay),
        output = output,
    )
    login_text = String(take!(output))
    @test backend isa PkgFactory.GitHubAPI
    @test backend.access_token == "oauth-secret-token"
    @test delays == [5, 5]
    @test occursin("ABCD-1234", login_text)
    @test occursin("authorization completed", login_text)
    @test !occursin("oauth-secret-token", login_text)

    missing_scope_requester = function (method, url; headers, body, status_exception)
        response = endswith(url, "/device/code") ? Dict(
            "device_code" => "device-code",
            "user_code" => "ABCD-1234",
            "verification_uri" => "https://github.com/login/device",
            "expires_in" => 900,
            "interval" => 5,
        ) : Dict(
            "access_token" => "oauth-secret-token",
            "scope" => "read:user,repo",
        )
        return PkgFactory.WebAPI.HTTP.Response(
            200,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end
    @test_throws ErrorException PkgFactory.github_device_login(
        requester = missing_scope_requester,
        sleeper = _ -> nothing,
        output = IOBuffer(),
    )
end

@testset "verify_owner_name" begin
    @test "OK" == PkgFactory.Verifications.verify_owner_name("ohno")
    @test "OK" != PkgFactory.Verifications.verify_owner_name("")
end

@testset "verify_package_name" begin
    @test "OK" == PkgFactory.Verifications.verify_package_name("Physics")
    @test "OK" != PkgFactory.Verifications.verify_package_name("")
    @test "OK" != PkgFactory.Verifications.verify_package_name("JuliaPkg")
    @test "OK" != PkgFactory.Verifications.verify_package_name("JustInTime")
    @test "OK" != PkgFactory.Verifications.verify_package_name("algebra")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Linear_algebra")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Math+Physics")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Eigen京")
    @test "OK" != PkgFactory.Verifications.verify_package_name("VMC")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Cake")
    @test "OK" != PkgFactory.Verifications.verify_package_name("juliaCI")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Jump")
    @test "OK" != PkgFactory.Verifications.verify_package_name("VMCjl")
    @test "OK" != PkgFactory.Verifications.verify_package_name("VMC.jl")
end

@testset "get_template_path" begin
    path_dir = PkgFactory.Templates.get_template_path("all-in-one")
    @test isdir(path_dir)
    @test occursin("all-in-one", path_dir)
end

@testset "list_templates" begin
    template_names = PkgFactory.Templates.list_templates()
    @test template_names == sort(template_names)
    @test "all-in-one" in template_names
    @test "minimum" in template_names
    @test "simple" in template_names
end

@testset "list_files" begin
    path_dir = PkgFactory.Templates.get_template_path("all-in-one")
    path_files = PkgFactory.Templates.list_files(path_dir)
    @test 0 < length(path_files)
    @test 0 < sum(occursin("README.md", path_file) for path_file in path_files)
    @test 0 < sum(occursin("LICENSE", path_file) for path_file in path_files)
    @test 0 == sum(occursin("aaaaa", path_file) for path_file in path_files)
end

@testset "read_file" begin
    path_dir = PkgFactory.Templates.get_template_path("all-in-one")
    path_files = PkgFactory.Templates.list_files(path_dir)
    path_file =
        path_files[findfirst(occursin("README.md", path_file) for path_file in path_files)]
    text = PkgFactory.Templates.read_file(path_file)
    @test 0 < length(path_file)
    @test occursin("README.md", path_file)
    @test 0 < length(text)
end

@testset "generate_template_files_dict" begin
    owner_name = "ohno"
    repo_name = "MyPkg.jl"
    author_names = ["Shuhei Ohno"]
    package_description = "My special package"
    template_name = "all-in-one"
    paths_and_contents = PkgFactory.Templates.generate_template_files_dict(
        owner_name,
        repo_name,
        author_names,
        package_description,
        template_name,
    )
    @test 0 < length(paths_and_contents)
    @test 0 < length(paths_and_contents["README.md"])
    @test occursin("MyPkg.jl", paths_and_contents["README.md"])
    @test occursin("Shuhei Ohno", paths_and_contents["LICENSE"])
    @test occursin("My special package", paths_and_contents["README.md"])
end

@testset "generated template contracts" begin
    render(template_name) = PkgFactory.Templates.generate_template_files_dict(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        template_name,
    )

    all_in_one = render("all-in-one")
    minimum = render("minimum")
    simple = render("simple")

    @test haskey(all_in_one, "src/MyPkg.jl")
    @test haskey(minimum, "src/MyPkg.jl")
    @test haskey(simple, "src/MyPkg.jl")
    for template in (all_in_one, simple, minimum)
        @test occursin("## Quick Start", template["README.md"])
        @test !occursin("## Installation", template["README.md"])
    end
    for template in (all_in_one, simple)
        @test occursin("## Quick Start", template["docs/src/index.md"])
        @test !occursin("## Installation", template["docs/src/index.md"])
    end
    @test occursin("version = \"0.0.1\"", all_in_one["Project.toml"])
    @test occursin("version = {v0.0.1}", all_in_one["CITATION.bib"])
    project_uuid = only(match(r"uuid = \"([^\"]+)\"", all_in_one["Project.toml"]).captures)
    @test occursin("MyPkg = \"$(project_uuid)\"", all_in_one["docs/Project.toml"])
    @test occursin("MyPkg = \"$(project_uuid)\"", all_in_one["test/Project.toml"])

    existing_uuid = "12345678-1234-5678-1234-567812345678"
    simple_with_existing_uuid = PkgFactory.Templates.generate_template_files_dict(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        "simple";
        package_uuid = existing_uuid,
    )
    @test occursin("uuid = \"$(existing_uuid)\"", simple_with_existing_uuid["Project.toml"])
    @test occursin(
        "MyPkg = \"$(existing_uuid)\"",
        simple_with_existing_uuid["docs/Project.toml"],
    )
    @test occursin(
        "MyPkg = \"$(existing_uuid)\"",
        simple_with_existing_uuid["test/Project.toml"],
    )

    @test !occursin("[extras]", all_in_one["Project.toml"])
    @test !occursin("[targets]", all_in_one["Project.toml"])
    @test !occursin("Aqua =", all_in_one["Project.toml"])
    @test !occursin("JET =", all_in_one["Project.toml"])
    @test !occursin("Test =", all_in_one["Project.toml"])
    @test occursin("julia = \"1.12\"", all_in_one["Project.toml"])
    @test occursin("[workspace]", all_in_one["Project.toml"])
    @test occursin("projects = [\"test\", \"docs\"]", all_in_one["Project.toml"])
    @test occursin("Aqua =", all_in_one["test/Project.toml"])
    @test occursin("JET = \"0.9, 0.10, 0.11, 0.12\"", all_in_one["test/Project.toml"])
    @test occursin("Test =", all_in_one["test/Project.toml"])
    @test occursin("Documenter = \"1\"", all_in_one["docs/Project.toml"])
    @test occursin("Julia-1.12+-blue.svg", all_in_one["README.md"])
    @test occursin("Julia-1.12+-blue.svg", all_in_one["docs/src/index.md"])

    @test !haskey(all_in_one, ".github/workflows/CompatHelper.yml")
    dependabot = all_in_one[".github/dependabot.yml"]
    @test occursin("package-ecosystem: \"github-actions\"", dependabot)
    @test occursin("package-ecosystem: \"julia\"", dependabot)
    for directory in ("/", "/docs", "/test")
        @test occursin("- \"$(directory)\"", dependabot)
    end

    all_ci = all_in_one[".github/workflows/CI.yml"]
    @test !occursin("version: 'min'", all_ci)
    @test count(==(true), occursin.("- '1.12'", eachline(IOBuffer(all_ci)))) == 2
    @test count(==(true), occursin.("- 'pre'", eachline(IOBuffer(all_ci)))) == 2
    @test occursin(raw"if: ${{ github.event_name == 'pull_request' }}", all_ci)
    @test occursin(raw"if: ${{ github.event_name != 'pull_request' }}", all_ci)
    @test occursin("- ubuntu-latest", all_ci)
    @test occursin("macOS-latest", all_ci)
    @test occursin("windows-latest", all_ci)
    @test occursin(raw"matrix.os == 'ubuntu-latest' && matrix.version == '1'", all_ci)
    @test occursin("JET_TEST:", all_ci)
    @test occursin("@static if get(ENV, \"JET_TEST\", \"true\") == \"true\"", all_in_one["test/runtests.jl"])

    @test occursin("```jldoctest", all_in_one["src/MyPkg.jl"])
    @test occursin("MyPkg.hello()", all_in_one["src/MyPkg.jl"])
    @test occursin("Return a friendly greeting.", all_in_one["src/MyPkg.jl"])
    @test !occursin("hello()::String", all_in_one["src/MyPkg.jl"])
    @test !occursin("#L", all_in_one["docs/src/developer.md"])
    @test occursin("[ColPrac version increment guidelines]", all_in_one["docs/src/developer.md"])
    @test occursin("[Quick Start](@ref)", all_in_one["docs/src/user.md"])
    @test !occursin("[Installation](@ref)", all_in_one["docs/src/user.md"])
    @test !occursin("```@index", all_in_one["docs/src/index.md"])
    @test occursin("import MyPkg # hide", all_in_one["docs/src/index.md"])
    @test occursin("pkgdir(MyPkg)", all_in_one["docs/src/index.md"])
    @test !occursin("../../CITATION.bib", all_in_one["docs/src/index.md"])
    @test occursin(r"month\s+= \{[a-z]{3}\}", all_in_one["CITATION.bib"])
    @test occursin("# Paste the complete output here.", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])
    @test !occursin("8fce2d05", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])
    @test !occursin("Julia Version 1.10.10", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])

    @test occursin("Documenter = \"1\"", simple["docs/Project.toml"])
    simple_project_uuid = only(match(r"uuid = \"([^\"]+)\"", simple["Project.toml"]).captures)
    @test occursin("MyPkg = \"$(simple_project_uuid)\"", simple["docs/Project.toml"])
    @test occursin("MyPkg = \"$(simple_project_uuid)\"", simple["test/Project.toml"])
    @test occursin("julia = \"1.12\"", simple["Project.toml"])
    @test occursin("projects = [\"test\", \"docs\"]", simple["Project.toml"])
    @test haskey(simple, "docs/make.jl")
    @test haskey(simple, "docs/src/index.md")
    @test haskey(simple, "docs/src/examples.md")
    @test haskey(simple, "docs/src/api.md")
    @test occursin("\"Home\" => \"index.md\"", simple["docs/make.jl"])
    @test occursin("\"Examples\" => \"examples.md\"", simple["docs/make.jl"])
    @test occursin("\"API Reference\" => \"api.md\"", simple["docs/make.jl"])
    @test occursin("# Examples", simple["docs/src/examples.md"])
    @test occursin("MyPkg.hello()", simple["docs/src/examples.md"])
    @test occursin("```@repl", simple["docs/src/examples.md"])
    @test occursin("```@example", simple["docs/src/examples.md"])
    @test occursin("Documenter", simple["docs/make.jl"])
    @test occursin("```jldoctest", simple["src/MyPkg.jl"])
    @test occursin("Test =", simple["test/Project.toml"])
    @test !occursin("DocStringExtensions", simple["Project.toml"])
    @test occursin("actions/workflows/CI.yml/badge.svg", simple["README.md"])
    @test occursin("docs-stable-blue.svg", simple["README.md"])
    @test occursin("codecov.io/gh/ohno/MyPkg.jl", simple["README.md"])
    @test occursin("Julia-1.12+-blue.svg", simple["README.md"])
    @test occursin("Julia-1.12+-blue.svg", simple["docs/src/index.md"])
    @test !occursin("github/license", simple["README.md"])
    @test !occursin("github/license", simple["docs/src/index.md"])
    @test occursin("API Reference", simple["README.md"])

    simple_ci = simple[".github/workflows/CI.yml"]
    @test !occursin("version: 'min'", simple_ci)
    @test count(==(true), occursin.("- '1.12'", eachline(IOBuffer(simple_ci)))) == 1
    @test count(==(true), occursin.("- 'pre'", eachline(IOBuffer(simple_ci)))) == 1
    @test !occursin("macOS-latest", simple_ci)
    @test !occursin("windows-latest", simple_ci)
    @test occursin(raw"continue-on-error: ${{ matrix.version == 'pre' }}", simple_ci)
    @test occursin("julia-actions/julia-runtest", simple_ci)
    @test occursin("julia-actions/julia-docdeploy", simple_ci)
    @test !occursin("JET_TEST", simple_ci)
    @test occursin("julia-actions/julia-processcoverage", simple_ci)
    @test occursin("codecov/codecov-action", simple_ci)
    @test occursin(raw"token: ${{ secrets.CODECOV_TOKEN }}", simple_ci)

    for path in (
        ".github/dependabot.yml",
        ".github/ISSUE_TEMPLATE/bug_report.md",
        ".github/ISSUE_TEMPLATE/feature_request.md",
        ".github/workflows/Format.yml",
        ".github/workflows/TagBot.yml",
        "CITATION.bib",
        "docs/src/developer.md",
        "docs/src/user.md",
    )
        @test !haskey(simple, path)
    end
    @test !any(
        occursin(dependency, content) for
            dependency in ("Aqua", "JET", "Runic") for
            content in values(simple)
    )

    @test haskey(minimum, ".github/workflows/CI.yml")
    @test occursin("actions/workflows/CI.yml/badge.svg", minimum["README.md"])
    @test !occursin("github/license", minimum["README.md"])
    @test occursin("Pkg.add(url=", minimum["README.md"])
    @test occursin("MyPkg.hello()", minimum["README.md"])
    minimum_ci = minimum[".github/workflows/CI.yml"]
    @test !occursin("version: 'min'", minimum_ci)
    @test !occursin("version: 'pre'", minimum_ci)
    @test count(==(true), occursin.("version: '1.12'", eachline(IOBuffer(minimum_ci)))) == 1
    @test !occursin("matrix:", minimum_ci)
    @test !occursin("macOS-latest", minimum_ci)
    @test !occursin("windows-latest", minimum_ci)
    @test !occursin("[extras]", minimum["Project.toml"])
    @test !occursin("[targets]", minimum["Project.toml"])
    @test occursin("julia = \"1.12\"", minimum["Project.toml"])
    @test occursin("projects = [\"test\"]", minimum["Project.toml"])
    minimum_project_uuid = only(match(r"uuid = \"([^\"]+)\"", minimum["Project.toml"]).captures)
    @test occursin("MyPkg = \"$(minimum_project_uuid)\"", minimum["test/Project.toml"])
    @test occursin("Test =", minimum["test/Project.toml"])
    @test occursin("Julia-1.12+-blue.svg", minimum["README.md"])
    @test !any(startswith(path, "docs/") for path in keys(minimum))
    @test !haskey(minimum, "CITATION.bib")
    @test !occursin("CITATION", minimum["README.md"])
    @test !occursin("Documentation", minimum["README.md"])
    @test !any(
        occursin(dependency, content) for
            dependency in ("Documenter", "Codecov", "JET") for
            content in values(minimum)
    )
end

@testset "local API input normalization" begin
    @test "MyPkg.jl" == PkgFactory.LocalAPI._normalize_repo_name("MyPkg")
    @test "MyPkg.jl" == PkgFactory.LocalAPI._normalize_repo_name("MyPkg.jl")
    @test "MyPkg" == PkgFactory.LocalAPI._get_package_name("MyPkg.jl")
    @test occursin("MyPkg.jl", PkgFactory.LocalAPI.get_codecov_url("ohno", "MyPkg"))
end

@testset "local API authentication" begin
    runner = FakeCommandRunner()
    @test PkgFactory.LocalAPI.check_status_code(; command_runner = runner)

    runner = FakeCommandRunner(; authenticated = false)
    @test !PkgFactory.LocalAPI.check_status_code(; command_runner = runner)
end

@testset "GitHub account information" begin
    runner = FakeCommandRunner()
    user = PkgFactory.LocalAPI.get_authenticated_user(; command_runner = runner)
    @test user.login == "ohno"
    @test user.email == "59360244+ohno@users.noreply.github.com"

    owners = PkgFactory.LocalAPI.get_repository_owners(; command_runner = runner)
    @test getproperty.(owners, :login) == ["ohno", "AllowedOrg"]
    @test getproperty.(owners, :kind) == [:user, :organization]
    @test !any(owner.login == "DeniedOrg" for owner in owners)

    repository_names =
        PkgFactory.LocalAPI.get_repository_names("ohno"; command_runner = runner)
    @test repository_names == ["MyPkg.jl", "MyPkg1.jl", "MyPkg2.jl"]

    runner = FakeCommandRunner(; registered_package_names = ["MyPkg", "MyPkgTools"])
    package_names = PkgFactory.LocalAPI.get_registered_package_names(
        "MyPkg";
        command_runner = runner,
    )
    @test package_names == ["MyPkg", "MyPkgTools"]
    @test any(
        occursin("repos/JuliaRegistries/General/git/trees/master:M", command) for
        command in runner.commands
    )
end

@testset "create_package_with_jll" begin
    runner = FakeCommandRunner()
    codecov_token = "codecov-secret"
    private_key = "documenter-secret"

    result = PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg",
        ["Shuhei Ohno"],
        "My special package",
        codecov_token;
        command_runner = runner,
        key_generator = () -> ("ssh-ed25519 public", private_key),
    )

    @test result
    @test any(occursin("repo create", command) for command in runner.commands)
    @test any(occursin("auth setup-git", command) for command in runner.commands)
    @test any(occursin("remote add origin", command) for command in runner.commands)
    @test any(occursin("push -u origin main", command) for command in runner.commands)
    @test any(occursin("config user.name ohno", command) for command in runner.commands)
    @test any(
        occursin("config user.email 59360244+ohno@users.noreply.github.com", command) for
        command in runner.commands
    )
    @test any(occursin("git/ref/heads/main", command) for command in runner.commands)
    @test any(occursin("DOCUMENTER_KEY", command) for command in runner.commands)
    @test any(occursin("CODECOV_TOKEN", command) for command in runner.commands)
    @test !any(occursin(codecov_token, command) for command in runner.commands)
    @test !any(occursin(private_key, command) for command in runner.commands)
    @test codecov_token in runner.inputs
    @test private_key in runner.inputs

    setup_git_index =
        findfirst(occursin("auth setup-git", command) for command in runner.commands)
    @test !isnothing(setup_git_index)
    @test occursin(
        dirname(first(PkgFactory.LocalAPI.git_executable().exec)),
        runner.environments[setup_git_index]["PATH"],
    )

    create_index =
        findfirst(occursin("repo create", command) for command in runner.commands)
    main_ref_index =
        findfirst(occursin("git/ref/heads/main", command) for command in runner.commands)
    @test !isnothing(create_index)
    @test !isnothing(main_ref_index)
    @test create_index < main_ref_index

    runner_without_codecov = FakeCommandRunner()
    @test PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg",
        ["Shuhei Ohno"],
        "My special package";
        command_runner = runner_without_codecov,
        key_generator = () -> ("ssh-ed25519 public", "documenter-secret"),
    )
    @test !any(
        occursin("CODECOV_TOKEN", command) for command in runner_without_codecov.commands
    )

    runner_with_substring = FakeCommandRunner()
    substring_token = strip(" codecov-secret ")
    @test substring_token isa SubString{String}
    @test PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg",
        ["Shuhei Ohno"],
        "My special package",
        substring_token;
        command_runner = runner_with_substring,
        key_generator = () -> ("ssh-ed25519 public", "documenter-secret"),
    )
    @test "codecov-secret" in runner_with_substring.inputs
end

@testset "resume package creation" begin
    existing_uuid = "12345678-1234-5678-1234-567812345678"
    runner = FakeCommandRunner(
        repository_exists = true,
        project_file = "name = \"MyPkg\"\nuuid = \"$(existing_uuid)\"\n",
        gh_pages_exists = true,
        deploy_key_exists = true,
        documenter_secret_exists = true,
    )

    @test PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        "codecov-secret";
        resume = true,
        command_runner = runner,
        key_generator = () -> error("Keys must not be regenerated"),
    )
    @test !any(occursin("repo create", command) for command in runner.commands)
    @test any(occursin("clone --branch main --single-branch", command) for command in runner.commands)
    @test any(occursin("diff --cached --quiet", command) for command in runner.commands)
    @test any(occursin(" commit -m ", command) for command in runner.commands)
    @test any(occursin("push origin HEAD:main", command) for command in runner.commands)

    runner = FakeCommandRunner(
        repository_exists = true,
        project_file = "name = \"MyPkg\"\nuuid = \"$(existing_uuid)\"\n",
        staged_changes = false,
        gh_pages_exists = true,
        deploy_key_exists = true,
        documenter_secret_exists = true,
    )
    @test PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package";
        resume = true,
        command_runner = runner,
        key_generator = () -> error("Keys must not be regenerated"),
    )
    @test !any(occursin(" commit -m ", command) for command in runner.commands)
    @test !any(occursin("push origin HEAD:main", command) for command in runner.commands)

    runner = FakeCommandRunner(
        repository_exists = true,
        project_file = nothing,
        main_branch_exists = true,
        gh_pages_exists = true,
        deploy_key_exists = true,
        documenter_secret_exists = true,
    )
    @test PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package";
        resume = true,
        command_runner = runner,
        key_generator = () -> error("Keys must not be regenerated"),
    )
    @test any(occursin("clone --branch main --single-branch", command) for command in runner.commands)
    @test !any(occursin("repo create", command) for command in runner.commands)

    runner = FakeCommandRunner(
        repository_exists = true,
        project_file = nothing,
        main_branch_exists = false,
    )
    @test PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package";
        resume = true,
        command_runner = runner,
        key_generator = () -> ("ssh-ed25519 public", "documenter-secret"),
    )
    @test !any(occursin("repo create", command) for command in runner.commands)
    @test !any(occursin(" clone ", command) for command in runner.commands)
    @test any(occursin("push -u origin main", command) for command in runner.commands)

    runner =
        FakeCommandRunner(repository_exists = true, project_file = "name = \"OtherPkg\"\n")
    @test_throws ErrorException PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        "codecov-secret";
        resume = true,
        command_runner = runner,
    )
end

@testset "local API errors" begin
    runner = FakeCommandRunner(; authenticated = false)
    @test_throws ErrorException PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        "codecov-secret";
        command_runner = runner,
    )

    runner = FakeCommandRunner(; repository_exists = true)
    @test_throws ErrorException PkgFactory.LocalAPI.create_package_with_jll(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        "codecov-secret";
        command_runner = runner,
    )

    secret = "must-not-appear"
    failing_runner =
        function (cmd::Cmd; env::Dict{String,String}, input::Union{Nothing,String})
            return false, secret, "failed with $(secret)"
        end
    error_message = try
        PkgFactory.LocalAPI._run_command_or_throw(
            `fake command`;
            input = secret,
            redactions = [secret],
            command_runner = failing_runner,
        )
        ""
    catch e
        sprint(showerror, e)
    end
    @test !occursin(secret, error_message)
    @test occursin("[REDACTED]", error_message)
end

@testset "JLL executable paths" begin
    @test !isempty(string(PkgFactory.LocalAPI.git_executable()))
    @test !isempty(string(PkgFactory.LocalAPI.gh_executable()))
end

@testset "local UI package name suggestions" begin
    @test PkgFactory.LocalUI._suggest_package_names(
        "MyPkg.jl",
        ["MyPkg.jl", "MyPkg02.jl", "MyPkg63.jl"],
    ) == ["MyPkg64", "MyPkg65", "MyPkg66"]

    existing_repository_names =
        vcat(["MyPkg.jl"], ["MyPkg$(suffix).jl" for suffix = 1:64])
    input = IOBuffer(
        join(
            [
                "1",
                "MyPkg",
                "n",
                "",
                "Alice Smith",
                "My package description",
                "",
                "",
                "",
                "",
                "y",
            ],
            "\n",
        ) * "\n",
    )
    output = IOBuffer()
    creator = FakePackageCreator(Any[], true)

    @test PkgFactory.LocalUI.CLI(;
        input = input,
        output = output,
        environment = Dict{String,String}(),
        status_checker = () -> true,
        package_creator = creator,
        repository_checker = (owner, repo) -> repo == "MyPkg.jl",
        repository_names_provider = owner -> existing_repository_names,
        registered_package_names_provider = package -> String[],
        repository_owners_provider = () ->
            [(login = "ohno", name = "Shuhei OHNO", kind = :user),],
        templates_provider = () -> ["minimum", "all-in-one"],
    )

    text = String(take!(output))
    @test occursin("Repository ohno/MyPkg.jl already exists.", text)
    @test occursin("Available package name suggestions:", text)
    @test occursin("1. MyPkg65 (default)", text)
    @test occursin("2. MyPkg66", text)
    @test occursin("3. MyPkg67", text)
    @test only(creator.calls).args[2] == "MyPkg65.jl"
    @test !only(creator.calls).options.resume
end

@testset "registered package name suggestions" begin
    input = IOBuffer(
        join(
            [
                "1",
                "MyPkg",
                "",
                "Alice Smith",
                "My package description",
                "",
                "",
                "",
                "",
                "y",
            ],
            "\n",
        ) * "\n",
    )
    output = IOBuffer()
    creator = FakePackageCreator(Any[], true)

    @test PkgFactory.LocalUI.CLI(;
        input = input,
        output = output,
        environment = Dict{String,String}(),
        status_checker = () -> true,
        package_creator = creator,
        repository_checker = (owner, repo) -> false,
        repository_names_provider = owner -> String[],
        registered_package_names_provider = package -> ["MyPkg", "MyPkg1"],
        repository_owners_provider = () ->
            [(login = "ohno", name = "Shuhei OHNO", kind = :user),],
        templates_provider = () -> ["minimum", "all-in-one"],
    )

    text = String(take!(output))
    @test occursin("Package MyPkg is already registered.", text)
    @test occursin("1. MyPkg2 (default)", text)
    @test only(creator.calls).args[2] == "MyPkg2.jl"
    @test !only(creator.calls).options.resume
end

@testset "interactive local UI" begin
    input = IOBuffer(
        join(
            [
                "2",
                "invalid",
                "MyPkg",
                "Alice, Bob",
                "My package description",
                "3",
                "2",
                "",
                "codecov-secret",
                "",
                "y",
            ],
            "\n",
        ) * "\n",
    )
    output = IOBuffer()
    creator = FakePackageCreator(Any[], true)
    repository_owners = [
        (login = "ohno", name = "Shuhei OHNO", kind = :user),
        (login = "qumpoo", name = "QUMPOO", kind = :organization),
    ]

    @test PkgFactory.LocalUI.CLI(;
        input = input,
        output = output,
        environment = Dict{String,String}(),
        status_checker = () -> true,
        package_creator = creator,
        repository_checker = (owner, repo) -> false,
        registered_package_names_provider = package -> String[],
        repository_owners_provider = () -> repository_owners,
        templates_provider = () -> ["minimum", "all-in-one", "simple"],
    )

    text = String(take!(output))
    @test occursin("Invalid input", text)
    @test occursin("@ohno", text)
    @test occursin("@qumpoo", text)
    @test occursin("qumpoo/MyPkg.jl", text)
    @test occursin("Created: https://github.com/qumpoo/MyPkg.jl", text)
    @test !occursin("Resume its setup?", text)
    @test occursin("Select repository owner (default: 1):", text)
    @test occursin("Package templates available:", text)
    @test occursin("1. all-in-one (default)", text)
    @test occursin("2. simple", text)
    @test occursin("3. minimum", text)
    @test occursin("Select template (default: 1):", text)
    @test occursin("Package name (example: MyPkg):", text)
    @test occursin(
        "Authors (comma-separated; written to LICENSE) (example: Alice Smith, Bob Jones):",
        text,
    )
    @test occursin("Package description (example: Tools for data analysis):", text)
    @test occursin("Repository visibility:", text)
    @test occursin("1. public (default)", text)
    @test occursin("2. private", text)
    @test occursin("Select visibility (default: 1):", text)
    @test occursin("Initial commit message (default: Using PkgFactory.jl):", text)
    @test occursin(
        "Codecov token (optional, example: 01234567-89ab-cdef-0123-456789abcdef):",
        text,
    )
    @test occursin("How to get a Codecov upload token:", text)
    @test occursin("qumpoo Settings > Global Upload Token", text)
    @test occursin("https://docs.codecov.com/docs/codecov-tokens", text)
    @test occursin("Please answer y or n.", text)
    @test length(
        collect(eachmatch(r"Create this repository\? \(example: y\) \(y/n\):", text)),
    ) == 2
    @test occursin("Codecov:     configured", text)
    @test first(findfirst("Codecov token", text)) <
          first(findfirst("Package configuration", text)) <
          first(findfirst("Create this repository?", text))
    @test !occursin("codecov-secret", text)
    @test length(creator.calls) == 1

    call = only(creator.calls)
    @test call.args == (
        "qumpoo",
        "MyPkg.jl",
        ["Alice", "Bob"],
        "My package description",
        "codecov-secret",
    )
    @test call.options.template_name == "minimum"
    @test call.options.visibility == "private"
    @test call.options.commit_message == "Using PkgFactory.jl"
    @test !call.options.resume
    @test call.args[5] isa String
end

@testset "resume existing repository from local UI" begin
    input = IOBuffer(
        join(
            [
                "1",
                "MyPkg",
                "y",
                "Alice",
                "My package description",
                "",
                "",
                "",
                "",
                "y",
            ],
            "\n",
        ) * "\n",
    )
    output = IOBuffer()
    creator = FakePackageCreator(Any[], true)

    @test PkgFactory.LocalUI.CLI(;
        input = input,
        output = output,
        environment = Dict{String,String}(),
        status_checker = () -> true,
        package_creator = creator,
        repository_checker = (owner, repo) -> true,
        registered_package_names_provider =
            package -> error("Registered packages must not be loaded when resuming"),
        repository_owners_provider = () ->
            [(login = "ohno", name = "Shuhei OHNO", kind = :user),],
        templates_provider = () -> ["minimum", "all-in-one"],
    )

    text = String(take!(output))
    @test occursin("Repository ohno/MyPkg.jl already exists.", text)
    @test occursin("Resume its setup? (default: n) (y/n):", text)
    @test occursin("1. all-in-one (default)", text)
    @test occursin("Codecov:     skipped", text)
    @test only(creator.calls).args[5] == ""
    @test only(creator.calls).options.template_name == "all-in-one"
    @test only(creator.calls).options.resume
end

@testset "local UI cancellation" begin
    creator = FakePackageCreator(Any[], true)
    output = IOBuffer()
    @test !PkgFactory.LocalUI.CLI(;
        input = IOBuffer("n\n"),
        output = output,
        status_checker = () -> false,
        login_handler = () -> error("Login must not run"),
        package_creator = creator,
    )
    @test isempty(creator.calls)
    text = String(take!(output))
    @test occursin("Log in to GitHub now? (default: y) (y/n):", text)
    @test occursin("authentication is required", text)

    input = IOBuffer("1\nMyPkg\nAlice\nMy package description\n\n\n\n\nn\n")
    output = IOBuffer()
    @test !PkgFactory.LocalUI.CLI(;
        input = input,
        output = output,
        status_checker = () -> true,
        package_creator = creator,
        repository_checker = (owner, repo) -> false,
        registered_package_names_provider = package -> String[],
        repository_owners_provider = () ->
            [(login = "ohno", name = "Shuhei OHNO", kind = :user),],
        templates_provider = () -> ["all-in-one", "minimum"],
    )
    @test isempty(creator.calls)
    text = String(take!(output))
    @test occursin("Codecov:     skipped", text)
    @test occursin("no repository was created", text)
end

@testset "web OAuth device flow" begin
    calls = NamedTuple[]
    requester = function (method, url; headers, body, status_exception)
        push!(calls, (; method, url, headers, body, status_exception))
        response = if endswith(url, "/device/code")
            Dict(
                "device_code" => "device-code",
                "user_code" => "ABCD-1234",
                "verification_uri" => "https://github.com/login/device",
                "expires_in" => 900,
                "interval" => 5,
            )
        else
            Dict(
                "access_token" => "github-token",
                "token_type" => "bearer",
                "scope" => "read:user,repo",
            )
        end
        return PkgFactory.WebAPI.HTTP.Response(
            200,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end

    device = PkgFactory.WebAPI.device_flow_begin("client-id"; requester = requester)
    @test device["user_code"] == "ABCD-1234"
    @test occursin("client_id=client-id", calls[1].body)
    @test occursin(
        "scope=read:user%20read:org%20repo%20workflow",
        calls[1].body,
    )

    token = PkgFactory.WebAPI.device_flow_poll(
        "device-code",
        "client-id";
        requester = requester,
    )
    @test token["access_token"] == "github-token"
    @test occursin("device_code=device-code", calls[2].body)

    connection_error = try
        PkgFactory.WebAPI.device_flow_begin(
            "client-id";
            requester = (args...; kwargs...) -> error("internal network detail"),
        )
        nothing
    catch error
        error
    end
    @test connection_error isa PkgFactory.WebAPI.GitHubAPIError
    @test connection_error.status == 503
    @test !occursin("internal network detail", sprint(showerror, connection_error))
end

@testset "web GitHub repository owners" begin
    requester = function (method, url; headers, body, status_exception)
        @test method == "GET"
        @test any(header -> header == ("Authorization" => "Bearer token"), headers)
        response =
            endswith(url, "/user") ?
            Dict("login" => "ohno", "name" => "Shuhei OHNO") :
            [Dict("login" => "ZetaOrg"), Dict("login" => "AlphaOrg")]
        return PkgFactory.WebAPI.HTTP.Response(
            200,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end

    owners = PkgFactory.WebAPI.get_repository_owners("token"; requester = requester)
    @test getindex.(owners, "login") == ["ohno", "AlphaOrg", "ZetaOrg"]
    @test getindex.(owners, "kind") == ["user", "organization", "organization"]

    personal_only_requester = function (method, url; headers, body, status_exception)
        response = endswith(url, "/user") ? Dict("login" => "ohno", "name" => nothing) :
                   Dict("message" => "Resource not accessible by integration")
        status = endswith(url, "/user") ? 200 : 403
        return PkgFactory.WebAPI.HTTP.Response(
            status,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end
    personal_only = PkgFactory.WebAPI.get_repository_owners(
        "token";
        requester = personal_only_requester,
    )
    @test personal_only == [
        Dict{String,Any}("login" => "ohno", "name" => "ohno", "kind" => "user"),
    ]
end

@testset "web GitHub repository availability" begin
    statuses = [404, 200]
    requester = function (method, url; headers, body, status_exception)
        @test method == "GET"
        @test endswith(url, "/repos/ohno/MyPackage.jl")
        status = popfirst!(statuses)
        response = status == 404 ? Dict("message" => "Not Found") : Dict("name" => "MyPackage.jl")
        return PkgFactory.WebAPI.HTTP.Response(
            status,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end

    available = PkgFactory.WebAPI.repository_availability(
        "token",
        "ohno",
        "MyPackage";
        requester = requester,
    )
    existing = PkgFactory.WebAPI.repository_availability(
        "token",
        "ohno",
        "MyPackage.jl";
        requester = requester,
    )
    @test available == Dict("available" => true, "repository" => "ohno/MyPackage.jl")
    @test existing == Dict("available" => false, "repository" => "ohno/MyPackage.jl")
    @test_throws ErrorException PkgFactory.WebAPI.repository_availability(
        "token",
        "ohno",
        "lowercase";
        requester = requester,
    )
end

@testset "web GitHub branch initialization delay" begin
    attempts = Ref(0)
    delays = Float64[]
    requester = function (method, url; headers, body, status_exception)
        attempts[] += 1
        status, response =
            attempts[] < 3 ?
            (404, Dict("message" => "Not Found")) :
            (200, Dict("object" => Dict("sha" => "initial-sha")))
        return PkgFactory.WebAPI.HTTP.Response(
            status,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end
    sha = PkgFactory.WebAPI._branch_head(
        "token",
        "ohno",
        "MyPackage.jl",
        "main";
        requester = requester,
        sleeper = delay -> push!(delays, delay),
    )
    @test sha == "initial-sha"
    @test attempts[] == 3
    @test delays == [1.0, 2.0]

    error = try
        PkgFactory.WebAPI._branch_head(
            "token",
            "ohno",
            "MyPackage.jl",
            "missing";
            requester = (args...; kwargs...) -> PkgFactory.WebAPI.HTTP.Response(
                404,
                PkgFactory.WebAPI.JSON3.write(Dict("message" => "Not Found")),
            ),
            attempts = 1,
            sleeper = _ -> nothing,
        )
        nothing
    catch caught
        caught
    end
    @test error isa PkgFactory.WebAPI.GitHubAPIError
    @test occursin("GET /repos/ohno/MyPackage.jl/git/ref/heads/missing", error.message)
end

@testset "create package through GitHub API" begin
    calls = NamedTuple[]
    requester = function (method, url; headers, body, status_exception)
        push!(calls, (; method, url, body))
        status, response = if method == "GET" && endswith(url, "/user")
            200, Dict("login" => "ohno")
        elseif method == "GET" && endswith(url, "/repos/ohno/MyPackage.jl")
            404, Dict("message" => "Not Found")
        elseif method == "POST" && endswith(url, "/user/repos")
            201, Dict("name" => "MyPackage.jl", "default_branch" => "main")
        elseif method == "GET" && endswith(url, "/contents/Project.toml")
            404, Dict("message" => "Not Found")
        elseif method == "GET" && endswith(url, "/git/ref/heads/main")
            200, Dict("object" => Dict("sha" => "parent-sha"))
        elseif method == "GET" && endswith(url, "/git/commits/parent-sha")
            200, Dict("tree" => Dict("sha" => "base-tree"))
        elseif method == "POST" && endswith(url, "/git/trees")
            201, Dict("sha" => "new-tree")
        elseif method == "POST" && endswith(url, "/git/commits")
            201, Dict("sha" => "package-commit")
        elseif method == "PATCH" && endswith(url, "/git/refs/heads/main")
            200, Dict("object" => Dict("sha" => "package-commit"))
        elseif method == "GET" && endswith(url, "/git/ref/heads/gh-pages")
            404, Dict("message" => "Not Found")
        elseif method == "POST" && endswith(url, "/git/refs")
            201, Dict("ref" => "refs/heads/gh-pages")
        elseif method == "GET" && endswith(url, "/keys?per_page=100")
            200, [Dict("title" => "Documenter")]
        else
            error("Unexpected GitHub request: $(method) $(url)")
        end
        return PkgFactory.WebAPI.HTTP.Response(
            status,
            PkgFactory.WebAPI.JSON3.write(response),
        )
    end

    result = PkgFactory.WebAPI.create_package(
        "token",
        "ohno",
        "MyPackage",
        ["Alice Smith"],
        "A package created in the browser";
        template_name = "minimum",
        requester = requester,
        key_generator = () -> error("Existing Documenter key should be reused"),
    )

    @test result["repository"] == "ohno/MyPackage.jl"
    @test result["url"] == "https://github.com/ohno/MyPackage.jl"
    @test !result["resumed"]
    @test any(call -> call.method == "POST" && endswith(call.url, "/user/repos"), calls)
    tree_call = only(filter(call -> endswith(call.url, "/git/trees"), calls))
    tree_body = PkgFactory.WebAPI.JSON3.read(tree_call.body, Dict{String,Any})
    @test tree_body["base_tree"] == "base-tree"
    @test any(entry -> entry["path"] == "Project.toml", tree_body["tree"])
    pages_call = only(filter(
        call -> call.method == "POST" && endswith(call.url, "/git/refs"),
        calls,
    ))
    @test occursin("refs/heads/gh-pages", pages_call.body)
end

@testset "web repository secret encryption" begin
    encrypted_request = Ref("")
    public_key = PkgFactory.WebAPI.Base64.base64encode(zeros(UInt8, 32))
    requester = function (method, url; headers, body, status_exception)
        if method == "GET"
            return PkgFactory.WebAPI.HTTP.Response(
                200,
                PkgFactory.WebAPI.JSON3.write(
                    Dict("key" => public_key, "key_id" => "key-id"),
                ),
            )
        end
        encrypted_request[] = body
        return PkgFactory.WebAPI.HTTP.Response(201, "")
    end

    PkgFactory.WebAPI._set_repository_secret(
        "token",
        "ohno",
        "MyPackage.jl",
        "TEST_SECRET",
        "secret";
        requester = requester,
    )
    request_body =
        PkgFactory.WebAPI.JSON3.read(encrypted_request[], Dict{String,Any})
    ciphertext =
        PkgFactory.WebAPI.Base64.base64decode(request_body["encrypted_value"])
    @test request_body["key_id"] == "key-id"
    @test length(ciphertext) == 6 + 48
end

@testset "web UI HTTP routes" begin
    root = PkgFactory.WebUI.handle_request(
        PkgFactory.WebUI.HTTP.Request("GET", "/"),
    )
    @test root.status == 200
    @test occursin("PkgFactory", String(root.body))
    @test occursin("Create repository", String(root.body))
    @test occursin("Generate package template", String(root.body))
    @test occursin("value=\"MyPkg\"", String(root.body))
    @test occursin("workflow, profile", String(root.body))
    @test occursin("contains only its initial README", String(root.body))
    @test occursin("default-src", PkgFactory.WebUI.HTTP.header(
        root,
        "Content-Security-Policy",
    ))

    stylesheet = PkgFactory.WebUI.handle_request(
        PkgFactory.WebUI.HTTP.Request("GET", "/style.css"),
    )
    javascript = PkgFactory.WebUI.handle_request(
        PkgFactory.WebUI.HTTP.Request("GET", "/app.js"),
    )
    @test stylesheet.status == 200
    @test occursin("prefers-color-scheme", String(stylesheet.body))
    @test javascript.status == 200
    @test occursin("connectGitHub", String(javascript.body))
    @test occursin("requiredScopes", String(javascript.body))
    @test occursin("setDefaultAuthor(owners[0])", String(javascript.body))
    @test occursin("checkPackageAvailability", String(javascript.body))
    @test occursin("package-availability", String(root.body))

    config = PkgFactory.WebUI.handle_request(
        PkgFactory.WebUI.HTTP.Request("GET", "/api/config");
        client_id = "test-client",
    )
    config_body = PkgFactory.WebAPI.JSON3.read(String(config.body), Dict{String,Any})
    @test config.status == 200
    @test config_body["client_id"] == "test-client"
    @test "all-in-one" in config_body["templates"]

    unauthorized = PkgFactory.WebUI.handle_request(
        PkgFactory.WebUI.HTTP.Request("GET", "/api/github/owners"),
    )
    @test unauthorized.status == 400
    @test occursin("authentication is required", String(unauthorized.body))

    availability_requester = function (method, url; headers, body, status_exception)
        @test method == "GET"
        @test endswith(url, "/repos/ohno/MyPackage.jl")
        return PkgFactory.WebAPI.HTTP.Response(
            404,
            PkgFactory.WebAPI.JSON3.write(Dict("message" => "Not Found")),
        )
    end
    availability = PkgFactory.WebUI.handle_request(
        PkgFactory.WebUI.HTTP.Request(
            "POST",
            "/api/github/repository-availability",
            ["Authorization" => "Bearer token"],
            PkgFactory.WebAPI.JSON3.write(
                Dict("owner" => "ohno", "package_name" => "MyPackage"),
            ),
        );
        requester = availability_requester,
    )
    availability_body = PkgFactory.WebAPI.JSON3.read(
        String(availability.body),
        Dict{String,Any},
    )
    @test availability.status == 200
    @test availability_body["available"]
    @test availability_body["repository"] == "ohno/MyPackage.jl"
end

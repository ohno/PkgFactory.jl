using PkgFactory
using Test

mutable struct FakeCommandRunner
    commands::Vector{String}
    environments::Vector{Dict{String,String}}
    inputs::Vector{Union{Nothing,String}}
    authenticated::Bool
    repository_exists::Bool
    project_file::Union{Nothing,String}
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
    project_file::Union{Nothing,String} = nothing,
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
        project_file,
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
    elseif occursin("api repos/", command) && occursin("--silent", command)
        return runner.repository_exists,
        "",
        runner.repository_exists ? "" : "HTTP 404: Not Found"
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
        return true, "abc123\n", ""
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

    @test haskey(all_in_one, "src/MyPkg.jl")
    @test haskey(minimum, "src/MyPkg.jl")
    @test occursin("version = \"0.0.1\"", all_in_one["Project.toml"])
    @test occursin("version = {v0.0.1}", all_in_one["CITATION.bib"])
    project_uuid = only(match(r"uuid = \"([^\"]+)\"", all_in_one["Project.toml"]).captures)
    @test occursin("MyPkg = \"$(project_uuid)\"", all_in_one["docs/Project.toml"])

    @test !occursin("[extras]", all_in_one["Project.toml"])
    @test !occursin("[targets]", all_in_one["Project.toml"])
    @test !occursin("Aqua =", all_in_one["Project.toml"])
    @test !occursin("JET =", all_in_one["Project.toml"])
    @test !occursin("Test =", all_in_one["Project.toml"])
    @test occursin("julia = \"1.10\"", all_in_one["Project.toml"])
    @test occursin("Aqua =", all_in_one["test/Project.toml"])
    @test occursin("JET = \"0.9, 0.10, 0.11, 0.12\"", all_in_one["test/Project.toml"])
    @test occursin("Test =", all_in_one["test/Project.toml"])
    @test occursin("Documenter = \"1\"", all_in_one["docs/Project.toml"])

    @test !haskey(all_in_one, ".github/workflows/CompatHelper.yml")
    dependabot = all_in_one[".github/dependabot.yml"]
    @test occursin("package-ecosystem: \"github-actions\"", dependabot)
    @test occursin("package-ecosystem: \"julia\"", dependabot)
    for directory in ("/", "/docs", "/test")
        @test occursin("- \"$(directory)\"", dependabot)
    end

    all_ci = all_in_one[".github/workflows/CI.yml"]
    @test occursin(raw"${{ matrix.version }}", all_ci)
    @test occursin("version: 'min'", all_ci)
    @test count(==(true), occursin.("coverage: true", eachline(IOBuffer(all_ci)))) == 1
    @test count(==(true), occursin.("jet: 'true'", eachline(IOBuffer(all_ci)))) == 1
    @test occursin("version: 'pre'", all_ci)
    @test occursin("continue-on-error:", all_ci)
    @test occursin("JET_TEST:", all_ci)
    @test occursin("@static if get(ENV, \"JET_TEST\", \"true\") == \"true\"", all_in_one["test/runtests.jl"])

    @test occursin("```jldoctest", all_in_one["src/MyPkg.jl"])
    @test occursin("MyPkg.hello()", all_in_one["src/MyPkg.jl"])
    @test occursin("Return a friendly greeting.", all_in_one["src/MyPkg.jl"])
    @test !occursin("hello()::String", all_in_one["src/MyPkg.jl"])
    @test !occursin("#L", all_in_one["docs/src/developer.md"])
    @test occursin("[ColPrac version increment guidelines]", all_in_one["docs/src/developer.md"])
    @test !occursin("```@index", all_in_one["docs/src/index.md"])
    @test occursin("import MyPkg # hide", all_in_one["docs/src/index.md"])
    @test occursin("pkgdir(MyPkg)", all_in_one["docs/src/index.md"])
    @test !occursin("../../CITATION.bib", all_in_one["docs/src/index.md"])
    @test occursin(r"month\s+= \{[a-z]{3}\}", all_in_one["CITATION.bib"])
    @test occursin("# Paste the complete output here.", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])
    @test !occursin("8fce2d05", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])
    @test !occursin("Julia Version 1.10.10", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])

    @test haskey(minimum, ".github/workflows/CI.yml")
    @test occursin("actions/workflows/CI.yml/badge.svg", minimum["README.md"])
    @test occursin("Pkg.add(url=", minimum["README.md"])
    @test occursin("MyPkg.hello()", minimum["README.md"])
    @test occursin(raw"${{ matrix.version }}", minimum[".github/workflows/CI.yml"])
    @test occursin("version: 'min'", minimum[".github/workflows/CI.yml"])
    @test occursin("version: 'pre'", minimum[".github/workflows/CI.yml"])
    @test !occursin("[extras]", minimum["Project.toml"])
    @test !occursin("[targets]", minimum["Project.toml"])
    @test occursin("julia = \"1.10\"", minimum["Project.toml"])
    @test occursin("Test =", minimum["test/Project.toml"])
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
    runner = FakeCommandRunner(
        repository_exists = true,
        project_file = "name = \"MyPkg\"\n",
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
    @test !any(occursin("git commit", command) for command in runner.commands)

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

@testset "interactive local UI" begin
    input = IOBuffer(
        join(
            [
                "2",
                "invalid",
                "MyPkg",
                "Alice, Bob",
                "My package description",
                "2",
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
        repository_owners_provider = () -> repository_owners,
        templates_provider = () -> ["all-in-one", "minimum"],
    )

    text = String(take!(output))
    @test occursin("Invalid input", text)
    @test occursin("@ohno", text)
    @test occursin("@qumpoo", text)
    @test occursin("qumpoo/MyPkg.jl", text)
    @test occursin("Created: https://github.com/qumpoo/MyPkg.jl", text)
    @test !occursin("Resume its setup?", text)
    @test occursin("Select repository owner (example: 1, default: 1):", text)
    @test occursin("Package templates available:", text)
    @test occursin("1. all-in-one (default)", text)
    @test occursin("2. minimum", text)
    @test occursin("Select template (example: 1, default: 1):", text)
    @test occursin("Package name (example: MyPkg):", text)
    @test occursin(
        "Authors (comma-separated; written to LICENSE) (example: Alice Smith, Bob Jones):",
        text,
    )
    @test occursin("Package description (example: Tools for data analysis):", text)
    @test occursin("Repository visibility:", text)
    @test occursin("1. public (default)", text)
    @test occursin("2. private", text)
    @test occursin("Select visibility (example: 2, default: 1):", text)
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
        repository_owners_provider = () ->
            [(login = "ohno", name = "Shuhei OHNO", kind = :user),],
        templates_provider = () -> ["minimum", "all-in-one"],
    )

    text = String(take!(output))
    @test occursin("Repository ohno/MyPkg.jl already exists.", text)
    @test occursin("Resume its setup? (example: y, default: n) (y/n):", text)
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
    @test occursin("Log in to GitHub now? (example: y, default: y) (y/n):", text)
    @test occursin("authentication is required", text)

    input = IOBuffer("1\nMyPkg\nAlice\nMy package description\n\n\n\n\nn\n")
    output = IOBuffer()
    @test !PkgFactory.LocalUI.CLI(;
        input = input,
        output = output,
        status_checker = () -> true,
        package_creator = creator,
        repository_checker = (owner, repo) -> false,
        repository_owners_provider = () ->
            [(login = "ohno", name = "Shuhei OHNO", kind = :user),],
        templates_provider = () -> ["all-in-one", "minimum"],
    )
    @test isempty(creator.calls)
    text = String(take!(output))
    @test occursin("Codecov:     skipped", text)
    @test occursin("no repository was created", text)
end

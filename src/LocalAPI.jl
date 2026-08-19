"""
This module contains the API for the local environment using the [Git.jl](https://github.com/JuliaVersionControl/Git.jl) and [GitHub CLI](https://github.com/JuliaBinaryWrappers/gh_cli_jll.jl).
"""
module LocalAPI

# Packages

import ..Templates
import ..Verifications
import Base64
import DocStringExtensions
import Git
import GitHub
import JSON3
import gh_cli_jll

function hello()
    return "Hello, LocalAPI.jl!"
end

# Functions

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.git_executable()
```
"""
function git_executable()
    return Git.git()
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.gh_executable()
```
"""
function gh_executable()
    return gh_cli_jll.gh()
end

function _git_path_environment()::Dict{String,String}
    separator = Sys.iswindows() ? ";" : ":"
    git_directory = dirname(first(git_executable().exec))
    path = join([git_directory, get(ENV, "PATH", "")], separator)
    return Dict("PATH" => path)
end

function _run_command(
    cmd::Cmd;
    env::Dict{String,String} = Dict{String,String}(),
    input::Union{Nothing,String} = nothing,
)
    out = IOBuffer()
    err = IOBuffer()
    command = addenv(cmd, env)
    process = if isnothing(input)
        run(pipeline(ignorestatus(command), stdout = out, stderr = err))
    else
        run(
            pipeline(
                ignorestatus(command),
                stdin = IOBuffer(input),
                stdout = out,
                stderr = err,
            ),
        )
    end
    stdout = String(take!(out))
    stderr = String(take!(err))
    return success(process), stdout, stderr
end

function _redact(text::String, redactions::Vector{String})::String
    for redaction in redactions
        isempty(redaction) || (text = replace(text, redaction => "[REDACTED]"))
    end
    return text
end

function _run_command_or_throw(
    cmd::Cmd;
    env::Dict{String,String} = Dict{String,String}(),
    input::Union{Nothing,String} = nothing,
    redactions::Vector{String} = String[],
    command_runner = _run_command,
)
    ok, stdout, stderr = command_runner(cmd; env = env, input = input)
    if !ok
        stdout = _redact(stdout, redactions)
        stderr = _redact(stderr, redactions)
        error("Command failed: $(cmd)\nSTDOUT:\n$(stdout)\nSTDERR:\n$(stderr)")
    end
    return stdout
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.check_status_code()
```
"""
function check_status_code(; command_runner = _run_command)::Bool
    ok, _, _ = command_runner(
        `$(gh_executable()) auth status`;
        env = Dict{String,String}(),
        input = nothing,
    )
    return ok
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.login()
```
"""
function login()::Bool
    process = run(ignorestatus(`$(gh_executable()) auth login`))
    return success(process)
end

const RepositoryOwner = NamedTuple{(:login, :name, :kind),Tuple{String,String,Symbol}}

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Return the authenticated GitHub user's commit identity.

```
PkgFactory.LocalAPI.get_authenticated_user()
```
"""
function get_authenticated_user(; command_runner = _run_command)
    response = _run_command_or_throw(
        `$(gh_executable()) api user`;
        command_runner = command_runner,
    )
    user = JSON3.read(response)
    login = String(user.login)
    user_id = Int(user.id)
    return (login = login, email = "$(user_id)+$(login)@users.noreply.github.com")
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Return the authenticated personal account and organizations where it can create repositories.

```
PkgFactory.LocalAPI.get_repository_owners()
```
"""
function get_repository_owners(; command_runner = _run_command)::Vector{RepositoryOwner}
    query = """
    query(\$endCursor: String) {
      viewer {
        login
        name
        organizations(first: 100, after: \$endCursor) {
          nodes {
            login
            name
            viewerCanCreateRepositories
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
    """
    response = _run_command_or_throw(
        `$(gh_executable()) api graphql --paginate --slurp -f query=$(query)`;
        command_runner = command_runner,
    )
    pages = JSON3.read(response)
    isempty(pages) && error("GitHub did not return an authenticated user.")

    viewer = first(pages).data.viewer
    login = String(viewer.login)
    name = isnothing(viewer.name) ? login : String(viewer.name)
    owners = RepositoryOwner[(login = login, name = name, kind = :user)]

    organizations = RepositoryOwner[]
    for page in pages
        for organization in page.data.viewer.organizations.nodes
            organization.viewerCanCreateRepositories || continue
            organization_login = String(organization.login)
            organization_name =
                isnothing(organization.name) ? organization_login :
                String(organization.name)
            push!(
                organizations,
                (
                    login = organization_login,
                    name = organization_name,
                    kind = :organization,
                ),
            )
        end
    end
    sort!(organizations; by = owner -> lowercase(owner.login))
    append!(owners, organizations)
    return owners
end

function _normalize_repo_name(repo_name::String)::String
    repo_name = strip(repo_name)
    return endswith(repo_name, ".jl") ? repo_name : "$(repo_name).jl"
end

function _get_package_name(repo_name::String)::String
    return replace(_normalize_repo_name(repo_name), r"\.jl$" => "")
end

function _verify_inputs(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    visibility::String,
)
    check_owner = Verifications.verify_owner_name(owner_name)
    check_owner == "OK" || error("Owner name is not valid: $(check_owner)")

    package_name = _get_package_name(repo_name)
    check_package = Verifications.verify_package_name(package_name)
    check_package == "OK" || error("Package name is not valid: $(check_package)")

    isempty(author_names) && error("Author names must not be empty.")
    any(isempty(strip(author_name)) for author_name in author_names) &&
        error("Author names must not contain an empty name.")
    visibility in ["public", "private"] ||
        error("Visibility must be either \"public\" or \"private\".")

    return _normalize_repo_name(repo_name)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.check_repo("ohno", "MyPkg.jl")
```
"""
function check_repo(
    owner_name::String,
    repo_name::String;
    command_runner = _run_command,
)::Bool
    repo_name = _normalize_repo_name(repo_name)
    cmd = `$(gh_executable()) api repos/$(owner_name)/$(repo_name) --silent`
    ok, stdout, stderr = command_runner(cmd; env = Dict{String,String}(), input = nothing)
    ok && return true
    occursin("404", stderr) && return false
    error("Command failed: $(cmd)\nSTDOUT:\n$(stdout)\nSTDERR:\n$(stderr)")
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

List repository names visible to the authenticated GitHub CLI account for an owner.

```
repository_names = PkgFactory.LocalAPI.get_repository_names("ohno")
```
"""
function get_repository_names(
    owner_name::String;
    command_runner = _run_command,
)::Vector{String}
    jq = ".[].name"
    response = _run_command_or_throw(
        `$(gh_executable()) repo list $(owner_name) --limit 1000 --json name --jq $(jq)`;
        command_runner = command_runner,
    )
    return filter(!isempty, strip.(split(response, '\n')))
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

List registered Julia package names that begin with the same letter as `package_name`.

```
package_names = PkgFactory.LocalAPI.get_registered_package_names("MyPkg")
```
"""
function get_registered_package_names(
    package_name::String;
    command_runner = _run_command,
)::Vector{String}
    check_package = Verifications.verify_package_name(package_name)
    check_package == "OK" || error("Package name is not valid: $(check_package)")

    initial = uppercase(first(package_name))
    jq = ".tree[].path"
    response = _run_command_or_throw(
        `$(gh_executable()) api repos/JuliaRegistries/General/git/trees/master:$(initial) --jq $(jq)`;
        command_runner = command_runner,
    )
    return filter(!isempty, strip.(split(response, '\n')))
end

function _get_project_file(
    owner_name::String,
    repo_name::String;
    command_runner = _run_command,
)
    repo_name = _normalize_repo_name(repo_name)
    cmd = `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/contents/Project.toml --jq .content`
    ok, stdout, stderr = command_runner(cmd; env = Dict{String,String}(), input = nothing)
    if ok
        encoded = replace(stdout, r"\s" => "")
        return String(Base64.base64decode(encoded))
    elseif occursin("404", stderr)
        return nothing
    end
    error("Command failed: $(cmd)\nSTDOUT:\n$(stdout)\nSTDERR:\n$(stderr)")
end

function _write_template_files(tempdir::String, paths_and_contents::Dict{String,String})
    for (path, content) in paths_and_contents
        file_path = joinpath(tempdir, split(path, "/")...)
        mkpath(dirname(file_path))
        Templates.write_file(file_path, content)
    end
    return true
end

function _create_local_commit(
    tempdir::String,
    git_user_name::String,
    git_user_email::String,
    commit_message::String;
    command_runner = _run_command,
)
    _run_command_or_throw(
        `$(git_executable()) -C $(tempdir) init`;
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(tempdir) checkout -b main`;
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(tempdir) config user.name $(git_user_name)`;
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(tempdir) config user.email $(git_user_email)`;
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(tempdir) add .`;
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(tempdir) commit -m $(commit_message)`;
        command_runner = command_runner,
    )
    return true
end

function _get_project_value(project_file::String, key::String)::Union{Nothing,String}
    value_match = match(Regex("(?m)^\\s*$(key)\\s*=\\s*\"([^\"]+)\""), project_file)
    return isnothing(value_match) ? nothing : String(value_match.captures[1])
end

function _main_branch_exists(
    owner_name::String,
    repo_name::String;
    command_runner = _run_command,
)::Bool
    repo_name = _normalize_repo_name(repo_name)
    cmd = `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/git/ref/heads/main --silent`
    ok, _, stderr = command_runner(cmd; env = Dict{String,String}(), input = nothing)
    ok && return true
    occursin("404", stderr) && return false
    error("Command failed: $(cmd)\nSTDERR:\n$(stderr)")
end

function _update_existing_package(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    template_name::String,
    commit_message::String;
    package_uuid::Union{Nothing,String} = nothing,
    command_runner = _run_command,
)::Bool
    repo_name = _normalize_repo_name(repo_name)
    paths_and_contents = Templates.generate_template_files_dict(
        owner_name,
        repo_name,
        author_names,
        package_description,
        template_name;
        package_uuid = package_uuid,
    )
    git_user = get_authenticated_user(; command_runner = command_runner)

    return mktempdir() do tempdir
        source_path = joinpath(tempdir, "repository")
        _run_command_or_throw(
            `$(gh_executable()) auth setup-git`;
            env = _git_path_environment(),
            command_runner = command_runner,
        )
        _run_command_or_throw(
            `$(git_executable()) clone --branch main --single-branch https://github.com/$(owner_name)/$(repo_name).git $(source_path)`;
            command_runner = command_runner,
        )
        _write_template_files(source_path, paths_and_contents)
        _run_command_or_throw(
            `$(git_executable()) -C $(source_path) config user.name $(git_user.login)`;
            command_runner = command_runner,
        )
        _run_command_or_throw(
            `$(git_executable()) -C $(source_path) config user.email $(git_user.email)`;
            command_runner = command_runner,
        )
        _run_command_or_throw(
            `$(git_executable()) -C $(source_path) add .`;
            command_runner = command_runner,
        )

        unchanged, _, stderr = command_runner(
            `$(git_executable()) -C $(source_path) diff --cached --quiet`;
            env = Dict{String,String}(),
            input = nothing,
        )
        unchanged && return false
        isempty(strip(stderr)) || error("Failed to inspect the rendered package changes: $(stderr)")

        _run_command_or_throw(
            `$(git_executable()) -C $(source_path) commit -m $(commit_message)`;
            command_runner = command_runner,
        )
        _run_command_or_throw(
            `$(git_executable()) -C $(source_path) push origin HEAD:main`;
            command_runner = command_runner,
        )
        return true
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.create_repo("ohno", "MyPkg.jl", "My special package")
```
"""
function create_repo(
    owner_name::String,
    repo_name::String,
    package_description::String;
    visibility::String = "public",
    command_runner = _run_command,
)
    repo_name = _normalize_repo_name(repo_name)
    visibility_option = visibility == "private" ? "--private" : "--public"
    homepage = "https://$(owner_name).github.io/$(repo_name)"
    _run_command_or_throw(
        `$(gh_executable()) repo create $(owner_name)/$(repo_name) $(visibility_option) --description $(package_description) --homepage $(homepage)`;
        command_runner = command_runner,
    )
    return true
end

function _push_initial_commit(
    owner_name::String,
    repo_name::String,
    source_path::String;
    command_runner = _run_command,
)
    repo_name = _normalize_repo_name(repo_name)
    _run_command_or_throw(
        `$(gh_executable()) auth setup-git`;
        env = _git_path_environment(),
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(source_path) remote add origin https://github.com/$(owner_name)/$(repo_name).git`;
        command_runner = command_runner,
    )
    _run_command_or_throw(
        `$(git_executable()) -C $(source_path) push -u origin main`;
        command_runner = command_runner,
    )
    return true
end

function _create_initial_commit(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    template_name::String,
    commit_message::String;
    visibility::String = "public",
    repository_exists::Bool = false,
    command_runner = _run_command,
)
    paths_and_contents = Templates.generate_template_files_dict(
        owner_name,
        repo_name,
        author_names,
        package_description,
        template_name,
    )
    git_user = get_authenticated_user(; command_runner = command_runner)

    mktempdir() do tempdir
        _write_template_files(tempdir, paths_and_contents)
        _create_local_commit(
            tempdir,
            git_user.login,
            git_user.email,
            commit_message;
            command_runner = command_runner,
        )
        if !repository_exists
            create_repo(
                owner_name,
                repo_name,
                package_description,
                visibility = visibility,
                command_runner = command_runner,
            )
        end
        _push_initial_commit(
            owner_name,
            repo_name,
            tempdir;
            command_runner = command_runner,
        )
    end
    return true
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.create_branch_gh_pages("ohno", "MyPkg.jl")
```
"""
function create_branch_gh_pages(
    owner_name::String,
    repo_name::String;
    command_runner = _run_command,
)::Bool
    repo_name = _normalize_repo_name(repo_name)
    branch_cmd = `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/git/ref/heads/gh-pages --silent`
    branch_exists, _, _ =
        command_runner(branch_cmd; env = Dict{String,String}(), input = nothing)
    branch_exists && return true

    main_ref = strip(
        _run_command_or_throw(
            `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/git/ref/heads/main --jq .object.sha`;
            command_runner = command_runner,
        ),
    )
    _run_command_or_throw(
        `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/git/refs --method POST -f ref=refs/heads/gh-pages -f sha=$(main_ref)`;
        command_runner = command_runner,
    )
    return true
end

function _repository_secret_exists(
    owner_name::String,
    repo_name::String,
    secret_name::String;
    command_runner = _run_command,
)::Bool
    repo_name = _normalize_repo_name(repo_name)
    jq = ".[].name"
    cmd = `$(gh_executable()) secret list --repo $(owner_name)/$(repo_name) --json name --jq $(jq)`
    ok, stdout, _ = command_runner(cmd; env = Dict{String,String}(), input = nothing)
    return ok && secret_name in split(stdout)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.set_repository_secret(
    "ohno",
    "MyPkg.jl",
    "CODECOV_TOKEN",
    "secret",
)
```
"""
function set_repository_secret(
    owner_name::String,
    repo_name::String,
    secret_name::String,
    secret_value::AbstractString;
    command_runner = _run_command,
)
    repo_name = _normalize_repo_name(repo_name)
    secret_value = String(secret_value)
    isempty(secret_value) && error("The repository secret must not be empty.")
    _run_command_or_throw(
        `$(gh_executable()) secret set $(secret_name) --repo $(owner_name)/$(repo_name)`;
        input = secret_value,
        redactions = [secret_value],
        command_runner = command_runner,
    )
    return true
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.get_codecov_url("ohno", "MyPkg.jl")
```
"""
function get_codecov_url(owner_name::String, repo_name::String)::String
    repo_name = _normalize_repo_name(repo_name)
    return "https://app.codecov.io/gh/$(owner_name)/$(repo_name)/new"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.set_codecov("ohno", "MyPkg.jl", "secret")
```
"""
function set_codecov(
    owner_name::String,
    repo_name::String,
    codecov_token::AbstractString;
    command_runner = _run_command,
)
    return set_repository_secret(
        owner_name,
        repo_name,
        "CODECOV_TOKEN",
        codecov_token;
        command_runner = command_runner,
    )
end

function _deploy_key_exists(
    owner_name::String,
    repo_name::String;
    command_runner = _run_command,
)::Bool
    repo_name = _normalize_repo_name(repo_name)
    jq = ".[].title"
    cmd = `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/keys --paginate --jq $(jq)`
    ok, stdout, _ = command_runner(cmd; env = Dict{String,String}(), input = nothing)
    return ok && "Documenter" in split(stdout, '\n'; keepempty = false)
end

function _generate_keys()
    return mktempdir() do tempdir
        cd(tempdir) do
            GitHub.genkeys()
        end
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.set_deploy_key("ohno", "MyPkg.jl")
```
"""
function set_deploy_key(
    owner_name::String,
    repo_name::String;
    command_runner = _run_command,
    key_generator = _generate_keys,
)
    repo_name = _normalize_repo_name(repo_name)
    key_exists = _deploy_key_exists(owner_name, repo_name; command_runner = command_runner)
    secret_exists = _repository_secret_exists(
        owner_name,
        repo_name,
        "DOCUMENTER_KEY";
        command_runner = command_runner,
    )
    key_exists && secret_exists && return true

    pubkey, privkey = key_generator()
    _run_command_or_throw(
        `$(gh_executable()) api repos/$(owner_name)/$(repo_name)/keys --method POST -f title=Documenter -f key=$(pubkey) -F read_only=false`;
        command_runner = command_runner,
    )
    set_repository_secret(
        owner_name,
        repo_name,
        "DOCUMENTER_KEY",
        privkey;
        command_runner = command_runner,
    )
    return true
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Create a GitHub repository, commit the generated package, and configure documentation and coverage secrets using the authenticated GitHub CLI session.

```
PkgFactory.LocalAPI.create_package_with_jll(
    "ohno",
    "MyPkg.jl",
    ["Shuhei Ohno"],
    "My special package",
    "codecov-token",
)
```
"""
function create_package_with_jll(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    codecov_token::AbstractString = "";
    template_name::String = "all-in-one",
    visibility::String = "public",
    commit_message::String = "Using PkgFactory.jl",
    resume::Bool = false,
    command_runner = _run_command,
    key_generator = _generate_keys,
)
    codecov_token = String(codecov_token)
    repo_name = _verify_inputs(owner_name, repo_name, author_names, visibility)
    check_status_code(; command_runner = command_runner) ||
        error("GitHub CLI is not authenticated. Run PkgFactory.LocalAPI.login() first.")

    repository_exists = check_repo(owner_name, repo_name; command_runner = command_runner)
    if repository_exists && !resume
        error(
            "The repository, \"$(owner_name)/$(repo_name)\" already exists. Set resume=true to continue an interrupted setup.",
        )
    end

    project_file = repository_exists ?
                   _get_project_file(owner_name, repo_name; command_runner = command_runner) :
                   nothing
    main_branch_exists = repository_exists && (
        !isnothing(project_file) ||
        _main_branch_exists(owner_name, repo_name; command_runner = command_runner)
    )
    if !repository_exists || !main_branch_exists
        _create_initial_commit(
            owner_name,
            repo_name,
            author_names,
            package_description,
            template_name,
            commit_message;
            visibility = visibility,
            repository_exists = repository_exists,
            command_runner = command_runner,
        )
    else
        package_name = _get_package_name(repo_name)
        package_uuid = nothing
        if !isnothing(project_file)
            _get_project_value(project_file, "name") == package_name || error(
                "The existing repository does not contain the expected package, \"$(package_name)\".",
            )
            package_uuid = _get_project_value(project_file, "uuid")
            isnothing(package_uuid) &&
                error("The existing package Project.toml does not contain a UUID.")
        end
        updated = _update_existing_package(
            owner_name,
            repo_name,
            author_names,
            package_description,
            template_name,
            commit_message;
            package_uuid = package_uuid,
            command_runner = command_runner,
        )
        if updated
            @info "The existing package files were updated."
        else
            @info "The existing package files already match the selected template."
        end
    end

    create_branch_gh_pages(owner_name, repo_name; command_runner = command_runner)
    set_deploy_key(
        owner_name,
        repo_name;
        command_runner = command_runner,
        key_generator = key_generator,
    )
    if isempty(strip(codecov_token))
        @info "Skipping the CODECOV_TOKEN repository secret."
    else
        set_codecov(owner_name, repo_name, codecov_token; command_runner = command_runner)
    end

    return true
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.LocalAPI.create_package(
    "ohno",
    "MyPkg.jl",
    ["Shuhei Ohno"],
    "My special package",
    "codecov-token",
)
```
"""
function create_package(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    codecov_token::AbstractString = "";
    kwargs...,
)
    try
        create_package_with_jll(
            owner_name,
            repo_name,
            author_names,
            package_description,
            codecov_token;
            kwargs...,
        )
        repo_name = _normalize_repo_name(repo_name)
        return "Success: $(repo_name) is created"
    catch e
        return "Error: $(sprint(showerror, e))"
    end
end

end

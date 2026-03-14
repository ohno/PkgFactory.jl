module PkgFactory

# Packages

import HTTP
import JSON3
import GitHub
import Sodium
import Base64
import URIs
import DocStringExtensions
import PkgTemplates
import Mustache
import UUIDs
import Dates
# import Oxygen

# Variables

const GITHUB_OAUTH_CLIENT_ID = "Ov23libqpCkC6Z5pSlFG"
const GITHUB_OAUTH_CLIENT_SECRET = "" # Device Flow

function hello()
    return "Hello, World!2"
end


function _run_command(cmd::Cmd; env::Dict{String,String}=Dict{String,String}())
    out = IOBuffer()
    err = IOBuffer()
    process = run(pipeline(ignorestatus(setenv(cmd, env)), stdout=out, stderr=err))
    stdout = String(take!(out))
    stderr = String(take!(err))
    return success(process), stdout, stderr
end

function _run_command_or_throw(cmd::Cmd; env::Dict{String,String}=Dict{String,String}())
    ok, stdout, stderr = _run_command(cmd; env=env)
    ok || error("Command failed: $(cmd)\nSTDOUT:\n$(stdout)\nSTDERR:\n$(stderr)")
    return stdout
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function git_executable()
    if Base.find_package("Git_jll") !== nothing
        @eval import Git_jll
        return Git_jll.git()
    end
    return "git"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function gh_executable()
    if Base.find_package("GitHub_jll") !== nothing
        @eval import GitHub_jll
        return GitHub_jll.gh()
    end
    return "gh"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function create_package_with_jll(
    access_token::String,
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String;
    commit_message::String = "Using PkgFactory.jl",
)
    gh_env = Dict("GH_TOKEN" => access_token)

    _run_command_or_throw(`$(gh_executable()) repo create $(owner_name)/$(repo_name) --public --description $(package_description) --homepage https://$(owner_name).github.io/$(repo_name) --confirm`; env=gh_env)

    pubkey, privkey = GitHub.genkeys()
    _run_command_or_throw(`$(gh_executable()) api repos/$(owner_name)/$(repo_name)/keys --method POST -f title=Documenter -f key=$(pubkey) -F read_only=false`; env=gh_env)
    _run_command_or_throw(`$(gh_executable()) secret set DEPLOY_KEY --repo $(owner_name)/$(repo_name) --body $(privkey)`; env=gh_env)

    main_ref = strip(_run_command_or_throw(`$(gh_executable()) api repos/$(owner_name)/$(repo_name)/git/ref/heads/main --jq .object.sha`; env=gh_env))
    _run_command_or_throw(`$(gh_executable()) api repos/$(owner_name)/$(repo_name)/git/refs --method POST -f ref=refs/heads/gh-pages -f sha=$(main_ref)`; env=gh_env)

    paths_and_contents = generate_template_dict(owner_name, repo_name, author_names, package_description)
    tempdir = mktempdir()

    _run_command_or_throw(`$(git_executable()) -C $(tempdir) init`)
    _run_command_or_throw(`$(git_executable()) -C $(tempdir) checkout -b main`)
    _run_command_or_throw(`$(git_executable()) -C $(tempdir) config user.name $(first(author_names))`)
    _run_command_or_throw(`$(git_executable()) -C $(tempdir) config user.email pkgfactory@example.com`)

    for (path, content) in paths_and_contents
        file_path = joinpath(tempdir, path)
        mkpath(dirname(file_path))
        write(file_path, content)
    end

    _run_command_or_throw(`$(git_executable()) -C $(tempdir) add .`)
    _run_command_or_throw(`$(git_executable()) -C $(tempdir) commit -m $(commit_message)`)

    _run_command_or_throw(`$(gh_executable()) auth setup-git`; env=gh_env)
    _run_command_or_throw(`$(git_executable()) -C $(tempdir) remote add origin https://github.com/$(owner_name)/$(repo_name).git`)
    _run_command_or_throw(`$(git_executable()) -C $(tempdir) push -u origin main`)

    return true
end

# Authorization

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function check_status_code()::Bool
    response = HTTP.get(
        "https://api.github.com/meta";
        retry = true,
        status_exception = false,
        headers = ["User-Agent" => "PkgFactory.jl"],
    )
    return response.status == 200
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function device_flow_begin(client_id::String)::JSON3.Object
    try
        response = HTTP.post(
            "https://github.com/login/device/code";
            headers = [
                "Accept" => "application/json",
                "Content-Type" => "application/x-www-form-urlencoded",
                "User-Agent" => "PkgFactory.jl",
            ],
            body = "client_id=$(client_id)&scope=read:user%20public_repo%20repo",
        )
        return JSON3.read(String(response.body))
    catch e
        # @error "device_flow_begin: $(e)"
        return JSON3.read(JSON3.write((
            device_code      = "",
            user_code        = "",
            verification_uri = "",
            expires_in       = 0,
            interval         = 0,
        )))
    end
end

# function device_flow_end(client_id::String, client_secret::String, device_code::String)
"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function device_flow_end(client_id::String, device_code::String)
    try
        response = HTTP.post(
            "https://github.com/login/oauth/access_token";
            headers = [
                "Accept" => "application/json",
                "Content-Type" => "application/x-www-form-urlencoded",
                "User-Agent" => "PkgFactory.jl",
            ],
            # body = "client_id=$(client_id)&device_code=$(device_code)&grant_type=urn:ietf:params:oauth:grant-type:device_code&client_secret=$(client_secret)"
            body = "client_id=$(client_id)&device_code=$(device_code)&grant_type=urn:ietf:params:oauth:grant-type:device_code",
        )
        return JSON3.read(String(response.body))
    catch e
        # @error "device_flow_end: $(e)"
        return JSON3.read(JSON3.write((
            access_token             = "",
            expires_in               = 0,
            refresh_token            = "",
            refresh_token_expires_in = 0,
            token_type               = "",
            scope                    = "",
        )))
    end
end

function authorize_user(client_id::String, client_secret::String)
    device_flow = device_flow_begin(client_id)
    if device_flow.device_code == ""
        return "Error: Failed to begin device flow"
    end
    device_flow_end(client_id, device_flow.device_code)
    if device_flow_end.access_token == ""
        return "Error: Failed to end device flow"
    end
    return device_flow_end.access_token
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function get_user_domain(access_token::String)
    auth = GitHub.authenticate(access_token)
    owner = GitHub.whoami(; auth=auth)
    orgs = GitHub.orgs(owner, auth=auth)
    return [owner.login, [org.login for org in orgs[1]]...]
end

# Repository

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function check_repo(access_token::String, owner_name::String, repo_name::String)
    try
        response = HTTP.get(
            "https://api.github.com/repos/$(owner_name)/$(repo_name)";
            headers = [
                "Accept" => "application/vnd.github+json",
                "Authorization" => "Bearer $(access_token)",
                "X-GitHub-Api-Version" => "2022-11-28",
                "User-Agent" => "PkgFactory.jl",
            ],
            status_exception = false,
        )
        return response.status == 200
    catch e
        return false
    end
end

"""
This function verifies the package name according to the [package naming rules](https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules) of [Pkg.jl](https://github.com/JuliaLang/Pkg.jl) and the [automatic merging guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) of [RegistryCI.jl](https://github.com/JuliaRegistries/RegistryCI.jl).

$(DocStringExtensions.TYPEDSIGNATURES)
"""
function verify_package_name(package_name::String)

    # Guidelines
    url_1 = "https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules"
    url_2 = "https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/"

    if isempty(package_name)
        return "The package name, \"$(package_name)\" must not be empty."
    end

    # https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules
    # 1. Avoid jargon. In particular, avoid acronyms unless there is minimal possibility of confusion.
    # 2. Avoid using Julia in your package name or prefixing it with Ju.

    if occursin("Julia", package_name)
        return "The package name, \"$(package_name)\" must not contain 'Julia'. See $(url_1)."
    end

    if startswith(package_name, "Ju")
        return "The package name, \"$(package_name)\" must not start with 'Ju'. See $(url_1)."
    end

    # 3. Packages that provide most of their functionality in association with a new type should have pluralized names.
    # 4. Err on the side of clarity, even if clarity seems long-winded to you.
    # 5. A less systematic name may suit a package that implements one of several possible approaches to its domain.
    # 6. Packages that wrap external libraries or programs can be named after those libraries or programs.
    # 7. Avoid naming a package closely to an existing package.
    # 8. Avoid using a distinctive name that is already in use in a well known, unrelated project.
    # 9. Packages should follow the Stylistic Conventions.

    if !isuppercase(package_name[1])
        return "The package name, \"$(package_name)\" must begin with a capital letter. See $(url_1)."
    end

    if occursin(r"[_\-]", package_name)
        return "The package name, \"$(package_name)\" must use upper camel case for word separation (no underscores or hyphens). See $(url_1)."
    end

    # https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/
    # 1. The package name, \"$(package_name)\" should be a valid Julia identifier (according to Base.isidentifier).

    if !Base.isidentifier(package_name)
        return "The package name, \"$(package_name)\" is not a valid Julia identifier. See $(url_2)."
    end

    # 2. The package name, \"$(package_name)\" should start with an upper-case letter, contain only ASCII alphanumeric characters, and contain at least one lowercase letter.

    if !isuppercase(package_name[1]) # not evaluated, already checked in the previous guideline
        return "The package name, \"$(package_name)\" must begin with a capital letter. See $(url_2)."
    end

    if !occursin(r"^[a-zA-Z0-9]+$", package_name)
        return "The package name, \"$(package_name)\" must contain only ASCII alphanumeric characters. See $(url_2)."
    end

    if all(isuppercase, package_name)
        return "The package name, \"$(package_name)\" must contain at least one lowercase letter. See $(url_2)."
    end

    # 3. The name is at least 5 characters long.

    if length(package_name) < 5
        return "The package name, \"$(package_name)\" must be at least 5 characters long. See $(url_2)."
    end

    # 4. Name does not include "julia", start with "Ju", or end with "jl".

    if occursin("julia", package_name) # not evaluated
        return "The package name, \"$(package_name)\" must not include 'julia'. See $(url_2)."
    end

    if startswith(package_name, "Ju") # not evaluated
        return "The package name, \"$(package_name)\" must not start with 'Ju'. See $(url_2)."
    end

    if endswith(package_name, "jl")
        return "The package name, \"$(package_name)\" must not end with 'jl'. See $(url_2)."
    end

    # 5. Repo URL ends with /PackageName.jl.git.

    if endswith(package_name, ".jl") # not evaluated
        return "The package name, \"$(package_name)\" must end with '.jl'. See $(url_2)."
    end

    # 6. Version number is not allowed to contain prerelease data
    # 7. Version number is not allowed to contain build data
    # 8. There is an upper-bounded [compat] entry for julia that only includes a finite number of breaking releases of Julia.
    # 9. Dependencies: All dependencies should have [compat] entries that are upper-bounded and only include a finite number of breaking releases. For more information, please see the "Upper-bounded [compat] entries" subsection under "Additional information" below.
    # 10. Name is composed of ASCII characters only.

    if !all(isascii, package_name) # not evaluated
        return "The package name, \"$(package_name)\" must contain only ASCII alphanumeric characters. See $(url_2)."
    end

    # 11. Package installation: The package should be installable (Pkg.add("PackageName")).
    # 12. Code can be downloaded.
    # 13. License: The package should have an OSI-approved software license located in the top-level directory of the package code, e.g. in a file named LICENSE or LICENSE.md. This check is required for the General registry. For other registries, registry maintainers have the option to disable this check.
    # 14. src files and directories names are OK
    # 15. Package loading: The package should be loadable (import PackageName).
    # 16. Packages must not match the name of existing package up-to-case, since on case-insensitive filesystems, this will break the registry.
    # 17. To prevent confusion between similarly named packages, the names of new packages must also satisfy the following three checks: (for more information, please see the "Name similarity distance check" subsection under "Additional information" below)

    return "OK"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function create_repo(access_token::String, owner_name::String, repo_name::String, package_description::String)
    owner = GitHub.owner(owner_name)
    if owner.typ == "User"
        url = "https://api.github.com/user/repos"
    elseif owner.typ == "Organization"
        url = "https://api.github.com/orgs/$(owner_name)/repos"
    end
    body = JSON3.write(Dict(
        "name" => repo_name,
        "description" => package_description,
        "private" => false,
        "homepage" => "https://$(owner_name).github.io/$(repo_name)",
        "auto_init" => true,
    )) # auto_init = true is required to use commit_files_on_github()
    try
        response = HTTP.post(
            url;
            headers = [
                "Accept" => "application/vnd.github+json",
                "Authorization" => "Bearer $(access_token)",
                "X-GitHub-Api-Version" => "2022-11-28",
                "User-Agent" => "PkgFactory.jl",
            ],
            body = body,
            status_exception = false,
        )
        return JSON3.read(String(response.body))
    catch e
        # error("Failed to create repository: $(response.status) - $(String(response.body))")
        return JSON3.read(JSON3.write((
            name = "",
            full_name = "",
            description = "",
        )))
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function create_branch_gh_pages(access_token::String, owner_name::String, repo_name::String)::Bool
    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)
    try
        sha = GitHub.reference(repo, "heads/main"; auth=auth).object["sha"]
        response = GitHub.create_reference(repo; auth=auth, params=Dict("ref" => "refs/heads/gh-pages", "sha" => sha))
        return true
    catch e
        return false
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function set_repository_secret(access_token::String, owner_name::String, repo_name::String, secret_name::String, secret_value::String)

    # https://github.com/JuliaWeb/GitHub.jl?tab=readme-ov-file#ssh-keys
    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)

    # get public key & encrypt
    gpk = GitHub.publickey(GitHub.DEFAULT_API, repo; auth=auth) # equal to GitHub.gh_get_json(GitHub.DEFAULT_API, "/repos/$(GitHub.name(repo))/actions/secrets/public-key"; auth=auth)
    encrypted = Sodium.seal(Vector{UInt8}(secret_value), gpk.key) # repair of GitHub.SodiumSeal.seal(base64encode(secret_value), GitHub.SodiumSeal.KeyPair(gpk.key))

    # set secret
    try
        response = GitHub.gh_put(
            GitHub.DEFAULT_API,
            "/repos/$(owner_name)/$(repo_name)/actions/secrets/$(secret_name)";
            handle_error = false,
            params = Dict(
                "encrypted_value" => encrypted,
                "key_id" => gpk.key_id,
            ),
            auth = auth,
        )
        return response.status in [201, 204]
    catch e
        return false
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function get_codecov_url(owner_name::String, repo_name::String)::String
    return "https://app.codecov.io/gh/$(owner_name)/$(repo_name)/new"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function set_codecov(access_token::String, owner_name::String, repo_name::String, codecov_token::String)
    return set_repository_secret(access_token, owner_name, repo_name, "CODECOV_TOKEN", codecov_token)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function set_deploy_key(access_token::String, owner_name::String, repo_name::String)
    # https://github.com/JuliaWeb/GitHub.jl?tab=readme-ov-file#ssh-keys
    pubkey, privkey = GitHub.genkeys()
    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)
    try
        response1 = GitHub.create_deploykey(
            repo;
            auth = auth,
            params = Dict(
                "key" => pubkey,
                "title" => "Documenter",
                "read_only" => false,
                "handle_error" => false,
            ),
        )
        response2 = PkgFactory.set_repository_secret(access_token, owner_name, repo_name, "DEPLOY_KEY", privkey)
        if !isnothing(response1.id) && response2
            return true
        else
            return false
        end
    catch e
        return false
    end
end

# Commit

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function get_file_on_github(access_token::String, owner_name::String, repo_name::String, repo_path::String)
    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)
    file = GitHub.file(repo, repo_path; auth = auth)
    return file
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function check_file_on_github(access_token::String, owner_name::String, repo_name::String, branch_name::String, repo_path::String)
    try
        get_file_on_github(access_token, owner_name, repo_name, repo_path)
        return true
    catch e
        return false
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function commit_file_on_github(access_token::String, owner_name::String, repo_name::String, branch_name::String, commit_message::String, path::String, content::String)

    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)

    file = try
        @info "get_file_on_github: $(path)"
        get_file_on_github(access_token, owner_name, repo_name, path)
    catch
        @info "get_file_on_github: $(path) not found"
        nothing
    end

    if isnothing(file)
        params = Dict(
            "message" => commit_message,
            "content" => Base64.base64encode(content),
            "branch"  => branch_name,
        )
        GitHub.create_file(repo, path; auth = auth, params = params)
        @info "create_file: $(path)"
    else
        params = Dict(
            "message" => commit_message,
            "content" => Base64.base64encode(content),
            "branch"  => branch_name,
            "sha"     => file.sha,
        )
        GitHub.update_file(repo, path; auth = auth, params = params)
        @info "update_file: $(path)"
    end

end

"""
!!! warning
    This function does not work for initial commit.

Signature:

$(DocStringExtensions.TYPEDSIGNATURES)
    
Example:

```julia
access_token = "YOUR_ACCESS_TOKEN"
owner_name = "user"
repo_name = "my-github-repo"
branch_name = "main"
commit_message = "Update hello1.md and hello2.md"
paths_and_contents = Dict(
    "hello1.md" => "Hello, 1",
    "hello2.md" => "Hello, 2",
)

PkgFactory.commit_files_on_github(
    access_token,
    owner_name,
    repo_name,
    branch_name,
    commit_message,
    paths_and_contents,
)
```
"""
function commit_files_on_github(
    access_token::String,
    owner_name::String,
    repo_name::String,
    branch_name::String,
    commit_message::String,
    paths_and_contents::Dict{String, String},
)
    auth = GitHub.authenticate(access_token)
    repo = GitHub.repo("$(owner_name)/$(repo_name)"; auth = auth)

    ref_name = "heads/$branch_name"
    current_ref = GitHub.reference(repo, ref_name; auth=auth)
    latest_commit_sha = current_ref.object["sha"]
    latest_commit = GitHub.commit(repo, latest_commit_sha; auth=auth)
    base_tree_sha = latest_commit.sha
    tree_entries = []
    for (path, content) in paths_and_contents
        push!(tree_entries, Dict(
            "path" => path,
            "mode" => "100644",
            "type" => "blob",
            "content" => content
        ))
    end

    new_tree = GitHub.create_tree(repo; auth = auth, params = Dict(
        "tree" => tree_entries,
        "base_tree" => base_tree_sha,
    ))

    new_commit = GitHub.create_gitcommit(repo; auth = auth, params = Dict(
        "message" => commit_message,
        "tree" => new_tree.sha,
        "parents" => [latest_commit_sha],
    ))

    GitHub.update_reference(repo, current_ref; auth = auth, params = Dict(
        "ref" => ref_name,
        "sha" => new_commit.sha,
    ))
end

# Template

"""
!!! warning
    This function is only for developers. This function updates the template files in the `PkgFactory.jl/template` directory.

Signature:

$(DocStringExtensions.TYPEDSIGNATURES)

Example:

```julia
PkgFactory.update_template("OWNER_NAME", "template", ["AUTHOR1", "AUTHOR2"])
```
"""
function update_template(owner_name::String, repo_name::String, author_names::Vector{String})::Dict{String, String}
    template = PkgTemplates.Template(;
        dir = "$(@__DIR__)/../",
        user = owner_name,
        authors = author_names,
        julia = v"1.11",
        plugins = [
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Default-Plugins
            PkgTemplates.ProjectFile(; version = v"0.0.1"),
            PkgTemplates.SrcDir(),
            PkgTemplates.Tests(; project = true),
            PkgTemplates.Readme(),
            PkgTemplates.License(),
            # PkgTemplates.Git(; ignore = ["*/Manifest.toml"]),
            PkgTemplates.GitHubActions(; extra_versions = ["1.11"]),
            PkgTemplates.CompatHelper(),
            PkgTemplates.TagBot(),
            # PkgTemplates.Secret(),
            PkgTemplates.Dependabot(),
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Code-Coverage
            PkgTemplates.Codecov(),
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Documentation
            PkgTemplates.Documenter{PkgTemplates.GitHubActions}(),
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Miscellaneous
            PkgTemplates.Citation(; readme = true),
            # PkgTemplates.Formatter(),
        ],
    )
    return template(repo_name)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function list_files()
    return [joinpath(dir, f) for (dir, _, fs) in walkdir("$(dirname(@__FILE__()))/../template") for f in fs]
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function load_file(path::String)::String
    try
        file = open(path, "r")
        text = Base.read(file, String)
        close(file)
        return text
    catch
        return ""
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function generate_template_dict(owner_name::String, repo_name::String, author_names::Vector{String}, package_description::String)

    ctx = Dict(
        "PKG"      => replace(repo_name, ".jl" => ""),
        "REPO"     => repo_name,
        "OWNER"    => owner_name,
        "DESCR"    => package_description,
        "UUID"     => string(UUIDs.uuid4()),
        "AUTHORS"  => author_names,
        "LICENSOR" => join(author_names, ", "),
        "URL"      => "https://github.com/$(owner_name)/$(repo_name)",
        "VERSION"  => "v0.0.1",
        "YEAR"     => Dates.year(Dates.today()),
        "MONTH"    => Dates.month(Dates.today()),
    )

    paths_and_contents = Dict{String, String}()

    for path in PkgFactory.list_files()
        key = relpath(path, "$(@__DIR__)/../template")
        key = replace(key, "\\" => "/")
        if key == "src/PKG.jl"
            key = "src/$(ctx["PKG"]).jl"
        end
        text = PkgFactory.load_file(path)
        rendered = if key[end-3:end] == ".yml" && key[end-5:end] != "CI.yml"
            text
        else
            Mustache.render(text, ctx)
        end
        paths_and_contents[key] = rendered
    end
    
    return paths_and_contents

end

# UI

function create_package(owner_name::String, repo_name::String, author_names::Vector{String}, package_description::String, codecov_token::String)
    check_name = PkgFactory.verify_package_name(repo_name)
    if check_name != "OK"
        return "Error: Package name is not valid: $(check_name)"
    end
    PkgFactory.create_repo(PERSONAL_ACCESS_TOKEN, owner_name, repo_name, package_description)
    PkgFactory.set_deploy_key(PERSONAL_ACCESS_TOKEN, owner_name, repo_name)
    PkgFactory.get_codecov_url(owner_name, repo_name)
    PkgFactory.set_codecov(PERSONAL_ACCESS_TOKEN, owner_name, repo_name, codecov_token)    
    PkgFactory.create_branch_gh_pages(PERSONAL_ACCESS_TOKEN, owner_name, repo_name)
    paths_and_contents = PkgFactory.generate_template_dict(owner_name, repo_name, author_names, package_description)
    PkgFactory.commit_files_on_github(PERSONAL_ACCESS_TOKEN, owner_name, repo_name, "main", "Using PkgFactory.jl", paths_and_contents)
    return "Success: $(repo_name) is created"
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)
"""
function CLI()
    println("Creating package...")
end


# using HTTP
# using JSON3
# using Oxygen
# @oxidize

# function start(
#     host = get(ENV, "HOST", "0.0.0.0"),
#     port = parse(Int, get(ENV, "PORT", "8000")),
# )
#     @info "Starting PkgFactory.jl server at http://localhost:$(port)/"
#     App.serve(host = host, port = port, revise = :eager)
# end

# # staticfiles("$(@__DIR__)/html", "/")
# dynamicfiles("$(@__DIR__)/html", "/")

# @get "/hello" function (req::HTTP.Request)
#     return "Hello, World!"
# end

# @get "/random" function (req::HTTP.Request)
#     return rand()
# end

# @get "/authorize/{user}" function(req::HTTP.Request, user::String)
#   return "Authorize $user"
# end

# @get "/authorize/status" function(req::HTTP.Request)
#   status = Authorize.check_status_code()
#   return Dict("status" => status, "message" => status ? "GitHub API is accessible" : "GitHub API is not accessible")
# end

# @post "/authorize/device-flow" function(req::HTTP.Request)
#   try
#     body = JSON3.read(HTTP.body(req))
#     client_id = get(body, :client_id, "")

#     if isempty(client_id)
#       return (status = 400, body = Dict("error" => "client_id is required"))
#     end

#     result = Authorize.device_flow(client_id)
#     return result
#   catch e
#     return (status = 400, body = Dict("error" => "Invalid request: $(string(e))"))
#   end
# end

# @post "/authorize/access-token" function(req::HTTP.Request)
#   try
#     body = JSON3.read(HTTP.body(req))
#     client_id = get(body, :client_id, "")
#     client_secret = get(body, :client_secret, "")
#     device_code = get(body, :device_code, "")

#     if isempty(client_id) || isempty(client_secret) || isempty(device_code)
#       return (status = 400, body = Dict("error" => "client_id, client_secret, and device_code are required"))
#     end

#     access_token = Authorize.get_access_token(client_id, client_secret, device_code)
#     return Dict("access_token" => access_token)
#   catch e
#     return (status = 400, body = Dict("error" => "Invalid request: $(string(e))"))
#   end
# end

end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Configuration for a package repository created from a notebook or script.
Secrets are supplied separately to [`create!`](@ref) and are not stored here.

```julia
config = PkgFactory.PackageConfig(
    owner = "octocat",
    name = "MyPkg",
    authors = ["The Octocat"],
    description = "A package created from Jupyter",
)
```
"""
struct PackageConfig
    owner::String
    name::String
    authors::Vector{String}
    description::String
    template::String
    visibility::String
    commit_message::String
    resume::Bool
end

function PackageConfig(;
    owner::AbstractString,
    name::AbstractString = "MyPkg",
    authors::AbstractVector{<:AbstractString},
    description::AbstractString,
    template::AbstractString = "all-in-one",
    visibility::AbstractString = "public",
    commit_message::AbstractString = "Using PkgFactory.jl",
    resume::Bool = false,
)
    package_name = replace(strip(String(name)), r"\.jl$"i => "")
    return PackageConfig(
        strip(String(owner)),
        package_name,
        strip.(String.(authors)),
        strip(String(description)),
        String(template),
        String(visibility),
        String(commit_message),
        resume,
    )
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

A read-only preview of the repository and files that PkgFactory will create.
Construct plans with [`preview`](@ref).
"""
struct PackagePlan
    config::PackageConfig
    repository::String
    files::Vector{String}
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

GitHub API credentials for [`create!`](@ref). Displaying this object never
reveals its access token. Calling `GitHubAPI()` reads `GITHUB_TOKEN`, falling
back to `GH_TOKEN`.

```julia
github = PkgFactory.GitHubAPI(ENV["GITHUB_TOKEN"])
```
"""
struct GitHubAPI
    access_token::String

    function GitHubAPI(access_token::AbstractString)
        token = strip(String(access_token))
        isempty(token) && error("A GitHub access token is required.")
        return new(token)
    end
end

function GitHubAPI()
    token = get(ENV, "GITHUB_TOKEN", get(ENV, "GH_TOKEN", ""))
    isempty(strip(token)) && error(
        "Set GITHUB_TOKEN or GH_TOKEN, or call github_device_login().",
    )
    return GitHubAPI(token)
end

function Base.show(io::IO, backend::GitHubAPI)
    return print(io, "GitHubAPI(access_token=<redacted>)")
end

Base.show(io::IO, ::MIME"text/plain", backend::GitHubAPI) = show(io, backend)

function Base.show(io::IO, config::PackageConfig)
    return print(
        io,
        "PackageConfig(owner=",
        repr(config.owner),
        ", name=",
        repr(config.name),
        ", template=",
        repr(config.template),
        ", visibility=",
        repr(config.visibility),
        ")",
    )
end

Base.show(io::IO, ::MIME"text/plain", config::PackageConfig) = show(io, config)

function Base.show(io::IO, ::MIME"text/plain", plan::PackagePlan)
    config = plan.config
    println(io, "PkgFactory package plan")
    println(io, "  Repository: https://github.com/$(plan.repository)")
    println(io, "  Template:   $(config.template)")
    println(io, "  Visibility: $(config.visibility)")
    println(io, "  Authors:    $(join(config.authors, ", "))")
    println(io, "  Operation:  $(config.resume ? "resume" : "create")")
    println(io, "  Files ($(length(plan.files))):")
    for file in plan.files
        println(io, "    - $(file)")
    end
    print(io, "No changes have been made. Call create! to execute this plan.")
end

Base.show(io::IO, plan::PackagePlan) = show(io, MIME"text/plain"(), plan)

function _plan_files(config::PackageConfig)::Vector{String}
    template_path = Templates.get_template_path(config.template)
    return sort([
        begin
            path = replace(relpath(file, template_path), "\\" => "/")
            if path == "src/PKG.jl"
                "src/$(config.name).jl"
            elseif path == "examples/PKG.ipynb"
                "examples/$(config.name).ipynb"
            else
                path
            end
        end for file in Templates.list_files(template_path)
    ])
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Validate a [`PackageConfig`](@ref) and return a read-only package plan. This
function performs no network requests and does not modify GitHub.

```julia
plan = PkgFactory.preview(config)
display(plan)
```
"""
function preview(config::PackageConfig)::PackagePlan
    repo_name = WebAPI._verify_inputs(
        config.owner,
        config.name,
        config.authors,
        config.visibility,
        config.template,
    )
    isempty(config.description) && error("The package description must not be empty.")
    isempty(strip(config.commit_message)) && error("The commit message must not be empty.")
    return PackagePlan(
        config,
        "$(config.owner)/$(repo_name)",
        _plan_files(config),
    )
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Authorize a Jupyter or terminal session with GitHub's OAuth device flow. The
one-time code is printed, while the returned access token is held only inside
a redacted [`GitHubAPI`](@ref) object.

```julia
github = PkgFactory.github_device_login()
```
"""
function github_device_login(;
    client_id::String = WebAPI.GITHUB_OAUTH_CLIENT_ID,
    requester = WebAPI.HTTP.request,
    sleeper = sleep,
    output::IO = stdout,
)
    device = WebAPI.device_flow_begin(client_id; requester = requester)
    verification_uri = String(device["verification_uri"])
    user_code = String(device["user_code"])
    println(output, "Open $(verification_uri) and enter code $(user_code).")
    println(output, "Waiting for GitHub authorization…")
    flush(output)

    interval = max(Int(get(device, "interval", 5)), 5)
    expires_in = max(Int(get(device, "expires_in", 900)), 1)
    deadline = time() + expires_in
    while time() < deadline
        sleeper(interval)
        result = WebAPI.device_flow_poll(
            String(device["device_code"]),
            client_id;
            requester = requester,
        )
        if haskey(result, "access_token")
            granted_scopes = Set(filter(
                !isempty,
                split(String(get(result, "scope", "")), r"[\s,]+"),
            ))
            missing_scopes = setdiff(Set(["repo", "workflow"]), granted_scopes)
            isempty(missing_scopes) || error(
                "GitHub did not grant the required $(join(sort!(collect(missing_scopes)), ", ")) permission.",
            )
            println(output, "GitHub authorization completed.")
            flush(output)
            return GitHubAPI(String(result["access_token"]))
        end

        oauth_error = String(get(result, "error", ""))
        oauth_error == "authorization_pending" && continue
        if oauth_error == "slow_down"
            interval += max(Int(get(result, "interval", 5)), 5)
            continue
        end
        error(String(get(result, "error_description", "GitHub authorization failed.")))
    end
    error("GitHub authorization expired before it was completed.")
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Execute a package plan through the GitHub API. Only this step changes GitHub.
Pass optional secrets at execution time so they are not stored in the plan.

```julia
result = PkgFactory.create!(plan; backend = github)
```
"""
function create!(
    plan::PackagePlan,
    backend::GitHubAPI;
    codecov_token::AbstractString = "",
    requester = WebAPI.HTTP.request,
    key_generator = WebAPI._generate_keys,
    package_creator = WebAPI.create_package,
)
    config = plan.config
    return package_creator(
        backend.access_token,
        config.owner,
        config.name,
        config.authors,
        config.description,
        codecov_token;
        template_name = config.template,
        visibility = config.visibility,
        commit_message = config.commit_message,
        resume = config.resume,
        requester = requester,
        key_generator = key_generator,
    )
end

function create!(plan::PackagePlan; backend::GitHubAPI, kwargs...)
    return create!(plan, backend; kwargs...)
end

function create!(config::PackageConfig, backend::GitHubAPI; kwargs...)
    return create!(preview(config), backend; kwargs...)
end

function create!(config::PackageConfig; backend::GitHubAPI, kwargs...)
    return create!(config, backend; kwargs...)
end

"""
GitHub REST API operations used by the browser-based user interface.

Authentication uses GitHub's OAuth device flow. Access tokens are supplied by
the caller and are never persisted by this module.
"""
module WebAPI

import Base64
import DocStringExtensions
import GitHub
import HTTP
import JSON3
import Sodium

import ..Templates
import ..Verifications

const GITHUB_API_URL = "https://api.github.com"
const GITHUB_OAUTH_URL = "https://github.com/login"
const GITHUB_API_VERSION = "2022-11-28"
const GITHUB_OAUTH_CLIENT_ID = "Ov23libqpCkC6Z5pSlFG"

struct GitHubAPIError <: Exception
    status::Int
    message::String
end

Base.showerror(io::IO, error::GitHubAPIError) = print(io, error.message)

hello() = "Hello, WebAPI.jl!"

function _response_json(response)
    isempty(response.body) && return Dict{String,Any}()
    text = String(response.body)
    return startswith(strip(text), "[") ? JSON3.read(text, Vector{Any}) :
           JSON3.read(text, Dict{String,Any})
end

function _github_message(response)::String
    body = try
        _response_json(response)
    catch
        Dict{String,Any}()
    end
    message =
        body isa AbstractDict ?
        get(body, "message", "GitHub returned an unexpected response.") :
        "GitHub returned an unexpected response."
    return "GitHub API request failed ($(response.status)): $(message)"
end

function _request_json(
    method::String,
    url::String;
    token::AbstractString = "",
    body = nothing,
    expected::Tuple = (200,),
    requester = HTTP.request,
)
    headers = Pair{String,String}[
        "Accept" => "application/vnd.github+json",
        "User-Agent" => "PkgFactory.jl",
        "X-GitHub-Api-Version" => GITHUB_API_VERSION,
    ]
    isempty(token) || push!(headers, "Authorization" => "Bearer $(token)")
    payload = ""
    if !isnothing(body)
        push!(headers, "Content-Type" => "application/json")
        payload = JSON3.write(body)
    end
    response = try
        requester(
            method,
            url;
            headers = headers,
            body = payload,
            status_exception = false,
        )
    catch
        throw(
            GitHubAPIError(
                503,
                "Could not connect to GitHub. Check the network connection and try again.",
            ),
        )
    end
    response.status in expected || throw(
        GitHubAPIError(
            response.status,
            "$(_github_message(response)) ($(method) $(replace(url, GITHUB_API_URL => "")))",
        ),
    )
    return _response_json(response), response.status
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Begin GitHub's OAuth device flow. The returned code is intended to be shown in
the browser while the access token is polled separately.
"""
function device_flow_begin(
    client_id::String = GITHUB_OAUTH_CLIENT_ID;
    requester = HTTP.request,
)
    response = try
        requester(
            "POST",
            "$(GITHUB_OAUTH_URL)/device/code";
            headers = [
                "Accept" => "application/json",
                "Content-Type" => "application/x-www-form-urlencoded",
                "User-Agent" => "PkgFactory.jl",
            ],
            body = "client_id=$(client_id)&scope=read:user%20read:org%20repo%20workflow",
            status_exception = false,
        )
    catch
        throw(
            GitHubAPIError(
                503,
                "Could not connect to GitHub. Check the network connection and try again.",
            ),
        )
    end
    response.status == 200 || throw(GitHubAPIError(response.status, _github_message(response)))
    return _response_json(response)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Poll GitHub for the result of an OAuth device authorization request. Pending
and slow-down responses are returned unchanged so the browser can keep polling.
"""
function device_flow_poll(
    device_code::String,
    client_id::String = GITHUB_OAUTH_CLIENT_ID;
    requester = HTTP.request,
)
    isempty(strip(device_code)) && error("The device code must not be empty.")
    response = try
        requester(
            "POST",
            "$(GITHUB_OAUTH_URL)/oauth/access_token";
            headers = [
                "Accept" => "application/json",
                "Content-Type" => "application/x-www-form-urlencoded",
                "User-Agent" => "PkgFactory.jl",
            ],
            body = "client_id=$(client_id)&device_code=$(device_code)&grant_type=urn:ietf:params:oauth:grant-type:device_code",
            status_exception = false,
        )
    catch
        throw(
            GitHubAPIError(
                503,
                "Could not connect to GitHub. Check the network connection and try again.",
            ),
        )
    end
    response.status == 200 || throw(GitHubAPIError(response.status, _github_message(response)))
    return _response_json(response)
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Return the authenticated user and organizations visible to the OAuth token.
If organization membership is unavailable, the personal account remains usable.
"""
function get_repository_owners(access_token::AbstractString; requester = HTTP.request)
    viewer, _ = _request_json(
        "GET",
        "$(GITHUB_API_URL)/user";
        token = access_token,
        requester = requester,
    )
    login = String(viewer["login"])
    display_name = isnothing(get(viewer, "name", nothing)) ? login : String(viewer["name"])
    owners = Dict{String,Any}[
        Dict("login" => login, "name" => display_name, "kind" => "user"),
    ]

    organizations = try
        response, _ = _request_json(
            "GET",
            "$(GITHUB_API_URL)/user/orgs?per_page=100";
            token = access_token,
            requester = requester,
        )
        response
    catch error
        error isa GitHubAPIError && error.status == 403 || rethrow()
        Any[]
    end
    for organization in organizations
        organization_login = String(organization["login"])
        push!(
            owners,
            Dict(
                "login" => organization_login,
                "name" => organization_login,
                "kind" => "organization",
            ),
        )
    end
    length(owners) > 1 &&
        sort!(view(owners, 2:length(owners)); by = owner -> lowercase(owner["login"]))
    return owners
end

function _normalize_repo_name(repo_name::String)::String
    repo_name = strip(repo_name)
    return endswith(repo_name, ".jl") ? repo_name : "$(repo_name).jl"
end

_package_name(repo_name::String) = replace(_normalize_repo_name(repo_name), r"\.jl$" => "")

function _verify_inputs(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    visibility::String,
    template_name::String,
)
    owner_check = Verifications.verify_owner_name(owner_name)
    owner_check == "OK" || error("Owner name is not valid: $(owner_check)")
    package_check = Verifications.verify_package_name(_package_name(repo_name))
    package_check == "OK" || error("Package name is not valid: $(package_check)")
    isempty(author_names) && error("Author names must not be empty.")
    any(isempty(strip(author)) for author in author_names) &&
        error("Author names must not contain an empty name.")
    visibility in ("public", "private") ||
        error("Visibility must be either \"public\" or \"private\".")
    template_name in Templates.list_templates() ||
        error("Unknown package template: $(template_name)")
    return _normalize_repo_name(repo_name)
end

function _repository(access_token, owner_name, repo_name; requester = HTTP.request)
    return _request_json(
        "GET",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)";
        token = access_token,
        expected = (200, 404),
        requester = requester,
    )
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Check whether a package repository name is available for a GitHub owner.

```julia
PkgFactory.WebAPI.repository_availability("token", "octocat", "MyPkg")
```
"""
function repository_availability(
    access_token::String,
    owner_name::String,
    repo_name::String;
    requester = HTTP.request,
)
    owner_check = Verifications.verify_owner_name(owner_name)
    owner_check == "OK" || error("Owner name is not valid: $(owner_check)")
    package_name = _package_name(repo_name)
    package_check = Verifications.verify_package_name(package_name)
    package_check == "OK" || error("Package name is not valid: $(package_check)")
    normalized_repo_name = _normalize_repo_name(repo_name)
    _, status = _repository(
        access_token,
        owner_name,
        normalized_repo_name;
        requester = requester,
    )
    return Dict(
        "available" => status == 404,
        "repository" => "$(owner_name)/$(normalized_repo_name)",
    )
end

function _create_repository(
    access_token,
    owner_name,
    repo_name,
    description,
    visibility,
    viewer_login;
    requester = HTTP.request,
)
    endpoint =
        owner_name == viewer_login ? "$(GITHUB_API_URL)/user/repos" :
        "$(GITHUB_API_URL)/orgs/$(owner_name)/repos"
    response, _ = _request_json(
        "POST",
        endpoint;
        token = access_token,
        body = Dict(
            "name" => repo_name,
            "description" => description,
            "homepage" => "https://$(owner_name).github.io/$(repo_name)",
            "private" => visibility == "private",
            "auto_init" => true,
        ),
        expected = (201,),
        requester = requester,
    )
    return response
end

function _project_file(access_token, owner_name, repo_name; requester = HTTP.request)
    response, status = _request_json(
        "GET",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/contents/Project.toml";
        token = access_token,
        expected = (200, 404),
        requester = requester,
    )
    status == 404 && return nothing
    encoded = replace(String(response["content"]), r"\s" => "")
    return String(Base64.base64decode(encoded))
end

function _branch_head(
    access_token,
    owner_name,
    repo_name,
    branch;
    requester = HTTP.request,
    attempts::Int = 6,
    sleeper = sleep,
)
    attempts > 0 || error("Branch lookup attempts must be positive.")
    endpoint = "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/ref/heads/$(branch)"
    for attempt in 1:attempts
        try
            response, _ = _request_json(
                "GET",
                endpoint;
                token = access_token,
                requester = requester,
            )
            return String(response["object"]["sha"])
        catch error
            retryable = error isa GitHubAPIError && error.status == 404
            retryable && attempt < attempts || rethrow()
            sleeper(min(2.0^(attempt - 1), 5.0))
        end
    end
    error("The default branch could not be loaded.")
end

function _commit_template(
    access_token,
    owner_name,
    repo_name,
    branch,
    paths_and_contents,
    commit_message;
    requester = HTTP.request,
)
    parent_sha = _branch_head(
        access_token,
        owner_name,
        repo_name,
        branch;
        requester = requester,
    )
    commit, _ = _request_json(
        "GET",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/commits/$(parent_sha)";
        token = access_token,
        requester = requester,
    )
    entries = [
        Dict(
            "path" => path,
            "mode" => "100644",
            "type" => "blob",
            "content" => content,
        ) for (path, content) in sort!(collect(paths_and_contents); by = first)
    ]
    tree, _ = _request_json(
        "POST",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/trees";
        token = access_token,
        body = Dict("base_tree" => commit["tree"]["sha"], "tree" => entries),
        expected = (201,),
        requester = requester,
    )
    new_commit, _ = _request_json(
        "POST",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/commits";
        token = access_token,
        body = Dict(
            "message" => commit_message,
            "tree" => tree["sha"],
            "parents" => [parent_sha],
        ),
        expected = (201,),
        requester = requester,
    )
    _request_json(
        "PATCH",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/refs/heads/$(branch)";
        token = access_token,
        body = Dict("sha" => new_commit["sha"], "force" => false),
        requester = requester,
    )
    return String(new_commit["sha"])
end

function _ensure_main_branch(
    access_token,
    owner_name,
    repo_name,
    current_branch,
    commit_sha;
    requester = HTTP.request,
)
    current_branch == "main" && return
    _request_json(
        "POST",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/refs";
        token = access_token,
        body = Dict("ref" => "refs/heads/main", "sha" => commit_sha),
        expected = (201,),
        requester = requester,
    )
    _request_json(
        "PATCH",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)";
        token = access_token,
        body = Dict("default_branch" => "main"),
        requester = requester,
    )
end

function _ensure_gh_pages(access_token, owner_name, repo_name, commit_sha; requester = HTTP.request)
    _, status = _request_json(
        "GET",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/ref/heads/gh-pages";
        token = access_token,
        expected = (200, 404),
        requester = requester,
    )
    status == 200 && return
    _request_json(
        "POST",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/refs";
        token = access_token,
        body = Dict("ref" => "refs/heads/gh-pages", "sha" => commit_sha),
        expected = (201,),
        requester = requester,
    )
end

function _set_repository_secret(
    access_token,
    owner_name,
    repo_name,
    secret_name,
    secret_value;
    requester = HTTP.request,
)
    public_key, _ = _request_json(
        "GET",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/actions/secrets/public-key";
        token = access_token,
        requester = requester,
    )
    encrypted = Sodium.seal(collect(codeunits(String(secret_value))), public_key["key"])
    _request_json(
        "PUT",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/actions/secrets/$(secret_name)";
        token = access_token,
        body = Dict(
            "encrypted_value" => encrypted,
            "key_id" => public_key["key_id"],
        ),
        expected = (201, 204),
        requester = requester,
    )
end

function _generate_keys()
    return mktempdir() do directory
        cd(directory) do
            GitHub.genkeys()
        end
    end
end

function _ensure_documenter_key(
    access_token,
    owner_name,
    repo_name;
    requester = HTTP.request,
    key_generator = _generate_keys,
)
    keys, _ = _request_json(
        "GET",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/keys?per_page=100";
        token = access_token,
        requester = requester,
    )
    any(get(key, "title", "") == "Documenter" for key in keys) && return
    public_key, private_key = key_generator()
    _request_json(
        "POST",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/keys";
        token = access_token,
        body = Dict("title" => "Documenter", "key" => public_key, "read_only" => false),
        expected = (201,),
        requester = requester,
    )
    _set_repository_secret(
        access_token,
        owner_name,
        repo_name,
        "DOCUMENTER_KEY",
        private_key;
        requester = requester,
    )
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Create and bootstrap a Julia package repository entirely through the GitHub API.
An interrupted setup can be continued with `resume = true`; an unrelated
existing repository is never overwritten.
"""
function create_package(
    access_token::AbstractString,
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    codecov_token::AbstractString = "";
    template_name::String = "all-in-one",
    visibility::String = "public",
    commit_message::String = "Using PkgFactory.jl",
    resume::Bool = false,
    requester = HTTP.request,
    key_generator = _generate_keys,
)
    isempty(strip(access_token)) && error("A GitHub access token is required.")
    repo_name = _verify_inputs(
        owner_name,
        repo_name,
        author_names,
        visibility,
        template_name,
    )
    isempty(strip(commit_message)) && error("The commit message must not be empty.")

    viewer, _ = _request_json(
        "GET",
        "$(GITHUB_API_URL)/user";
        token = access_token,
        requester = requester,
    )
    repository, repository_status = _repository(
        access_token,
        owner_name,
        repo_name;
        requester = requester,
    )
    if repository_status == 200 && !resume
        error(
            "The repository, \"$(owner_name)/$(repo_name)\" already exists. Enable resume to continue an interrupted setup.",
        )
    elseif repository_status == 404
        repository = _create_repository(
            access_token,
            owner_name,
            repo_name,
            package_description,
            visibility,
            String(viewer["login"]);
            requester = requester,
        )
    end

    default_branch = String(get(repository, "default_branch", "main"))
    project_file = _project_file(
        access_token,
        owner_name,
        repo_name;
        requester = requester,
    )
    commit_sha = if isnothing(project_file)
        files = Templates.generate_template_files_dict(
            owner_name,
            repo_name,
            author_names,
            package_description,
            template_name,
        )
        _commit_template(
            access_token,
            owner_name,
            repo_name,
            default_branch,
            files,
            commit_message;
            requester = requester,
        )
    else
        package_name = _package_name(repo_name)
        occursin("name = \"$(package_name)\"", project_file) || error(
            "The existing repository does not contain the expected package, \"$(package_name)\".",
        )
        _branch_head(
            access_token,
            owner_name,
            repo_name,
            default_branch;
            requester = requester,
        )
    end

    _ensure_main_branch(
        access_token,
        owner_name,
        repo_name,
        default_branch,
        commit_sha;
        requester = requester,
    )
    if template_name != "minimum"
        _ensure_gh_pages(
            access_token,
            owner_name,
            repo_name,
            commit_sha;
            requester = requester,
        )
        _ensure_documenter_key(
            access_token,
            owner_name,
            repo_name;
            requester = requester,
            key_generator = key_generator,
        )
    end
    if template_name != "minimum" && !isempty(strip(codecov_token))
        _set_repository_secret(
            access_token,
            owner_name,
            repo_name,
            "CODECOV_TOKEN",
            String(codecov_token);
            requester = requester,
        )
    end

    return Dict(
        "repository" => "$(owner_name)/$(repo_name)",
        "url" => "https://github.com/$(owner_name)/$(repo_name)",
        "resumed" => repository_status == 200,
    )
end

end

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
import SHA
import URIs
import UUIDs

import ..Templates
import ..Verifications

const GITHUB_API_URL = "https://api.github.com"
const GITHUB_OAUTH_URL = "https://github.com/login"
const GITHUB_API_VERSION = "2022-11-28"
const GITHUB_OAUTH_CLIENT_ID = "Ov23libqpCkC6Z5pSlFG"

struct GitHubAPIError <: Exception
    status::Int
    message::String
    retry_after::Union{Nothing,Int}
end
GitHubAPIError(status::Int, message::String) = GitHubAPIError(status, message, nothing)

Base.showerror(io::IO, error::GitHubAPIError) = print(io, error.message)

hello() = "Hello, WebAPI.jl!"

include("WebSafety.jl")

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
    requester = GitHubTransport(),
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
    catch err
        err isa InterruptException && rethrow()
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
            tryparse(Int, HTTP.header(response, "Retry-After", "")),
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
    requester = GitHubTransport(),
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
            body = "client_id=$(URIs.escapeuri(client_id))&scope=read:user%20read:org%20repo%20workflow",
            status_exception = false,
        )
    catch err
        err isa InterruptException && rethrow()
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
    requester = GitHubTransport(),
)
    _bounded_text(device_code, "device_code", 1024)
    response = try
        requester(
            "POST",
            "$(GITHUB_OAUTH_URL)/oauth/access_token";
            headers = [
                "Accept" => "application/json",
                "Content-Type" => "application/x-www-form-urlencoded",
                "User-Agent" => "PkgFactory.jl",
            ],
            body = "client_id=$(URIs.escapeuri(client_id))&device_code=$(URIs.escapeuri(device_code))&grant_type=urn:ietf:params:oauth:grant-type:device_code",
            status_exception = false,
        )
    catch err
        err isa InterruptException && rethrow()
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
function get_repository_owners(access_token::AbstractString; requester = GitHubTransport())
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
    _validate_owner(owner_name)
    _bounded_text(repo_name, "package_name", 100)
    package_check = Verifications.verify_package_name(_package_name(repo_name))
    package_check == "OK" || throw(InputError("Invalid package name."))
    1 <= length(author_names) <= 20 || throw(InputError("authors must contain 1 to 20 names."))
    foreach(author -> _bounded_text(author, "author", 200), author_names)
    visibility in ("public", "private") ||
        throw(InputError("Visibility must be public or private."))
    template_name in Templates.list_templates() ||
        throw(InputError("Unknown package template."))
    return _normalize_repo_name(repo_name)
end

function _repository(access_token, owner_name, repo_name; requester = GitHubTransport())
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
    requester = GitHubTransport(),
)
    _validate_owner(owner_name)
    _bounded_text(repo_name, "package_name", 100)
    package_name = _package_name(repo_name)
    package_check = Verifications.verify_package_name(package_name)
    package_check == "OK" || throw(InputError("Invalid package name."))
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
    requester = GitHubTransport(),
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

function _project_file(access_token, owner_name, repo_name; requester = GitHubTransport())
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
    requester = GitHubTransport(),
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
    requester = GitHubTransport(),
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
    requester = GitHubTransport(),
)
    current_branch == "main" && return
    existing, status = _request_json("GET", "$GITHUB_API_URL/repos/$owner_name/$repo_name/git/ref/heads/main";
        token=access_token, expected=(200, 404), requester)
    if status == 200
        existing["object"]["sha"] == commit_sha || throw(InputError("Existing main branch has a different commit."))
    else
        _request_json(
            "POST",
            "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)/git/refs";
            token = access_token,
            body = Dict("ref" => "refs/heads/main", "sha" => commit_sha),
            expected = (201,),
            requester = requester,
        )
    end
    _request_json(
        "PATCH",
        "$(GITHUB_API_URL)/repos/$(owner_name)/$(repo_name)";
        token = access_token,
        body = Dict("default_branch" => "main"),
        requester = requester,
    )
end

function _ensure_gh_pages(access_token, owner_name, repo_name, commit_sha; requester = GitHubTransport())
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
    requester = GitHubTransport(),
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
        filename = joinpath(directory, "documenter")
        # No process-global cd and no shared relative filenames.
        run(pipeline(`ssh-keygen -q -t rsa -b 4096 -N "" -C Documenter -f $filename`;
            stdout=devnull, stderr=devnull))
        (chomp(read(filename * ".pub", String)), Base64.base64encode(read(filename)))
    end
end

function _ensure_documenter_key(
    access_token,
    owner_name,
    repo_name;
    requester = GitHubTransport(),
    key_generator = _generate_keys,
)
    # Only remove keys created by this workflow. Always rotate on an explicit
    # resume: GitHub does not expose secret contents, so presence cannot prove
    # that an existing public key and secret form a pair.
    managed = Any[]
    for page in 1:10
        keys, _ = _request_json("GET",
            "$GITHUB_API_URL/repos/$owner_name/$repo_name/keys?per_page=100&page=$page";
            token=access_token, requester)
        append!(managed, filter(key -> startswith(get(key, "title", ""), "PkgFactory Documenter "), keys))
        length(keys) < 100 && break
        page == 10 && throw(InputError("Too many deploy keys; inspect the repository manually."))
    end
    public_key, private_key = key_generator()
    _request_json("POST", "$GITHUB_API_URL/repos/$owner_name/$repo_name/keys";
        token=access_token,
        body=Dict("title" => "PkgFactory Documenter $(UUIDs.uuid4())", "key" => public_key, "read_only" => false),
        expected=(201,), requester)
    _set_repository_secret(access_token, owner_name, repo_name, "DOCUMENTER_KEY", private_key; requester)
    # Leave both keys in place if secret upload fails or its result is unknown.
    # The next resume installs a fresh matching pair before cleaning old keys.
    for key in managed
        _request_json("DELETE", "$GITHUB_API_URL/repos/$owner_name/$repo_name/keys/$(key["id"])";
            token=access_token, expected=(204, 404), requester)
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Create and bootstrap a Julia package repository entirely through the GitHub API.
Resume requires a matching `.pkgfactory.json` marker committed with the template.
Unmarked repositories (including failures before that commit) require manual inspection.
"""
function _create_package(
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
    requester = GitHubTransport(),
    key_generator = _generate_keys,
    stage = Ref("validation"),
)
    _bounded_text(access_token, "access_token", 4096)
    repo_name = _verify_inputs(
        owner_name,
        repo_name,
        author_names,
        visibility,
        template_name,
    )
    _bounded_text(package_description, "description", 2000; empty=true)
    _bounded_text(commit_message, "commit_message", 500)
    _bounded_text(codecov_token, "codecov_token", 4096; empty=true)
    fingerprint = _fingerprint(owner_name, repo_name, author_names, package_description,
        template_name, visibility, commit_message)
    stage[] = "repository_lookup"

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
        throw(GitHubAPIError(409, "Repository already exists. Inspect its status before resuming."))
    elseif repository_status == 404
        stage[] = "repository_creation"
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

    stage[] = "recovery_validation"
    marker = repository_status == 200 ? _marker(access_token, owner_name, repo_name; requester) : nothing
    if repository_status == 200
        isnothing(marker) && throw(InputError("No PkgFactory recovery marker. Inspect the repository manually; automatic resume is refused."))
        get(marker.data, "fingerprint", "") == fingerprint ||
            throw(InputError("Settings differ from the original PkgFactory operation."))
    end
    default_branch = String(get(repository, "default_branch", "main"))
    project_file = _project_file(
        access_token,
        owner_name,
        repo_name;
        requester = requester,
    )
    if !isnothing(marker)
        !isnothing(project_file) && get(marker.data, "project_sha256", "") == bytes2hex(SHA.sha256(project_file)) ||
            throw(InputError("Project.toml changed since package generation; automatic resume is refused."))
        get(marker.data, "state", "") in ("files_committed", "complete") || throw(InputError("Invalid recovery state."))
        if marker.data["state"] == "complete"
            return Dict("repository" => "$owner_name/$repo_name", "url" => "https://github.com/$owner_name/$repo_name", "resumed" => true)
        end
    end
    stage[] = "template_commit"
    commit_sha = if isnothing(project_file)
        files = Templates.generate_template_files_dict(
            owner_name,
            repo_name,
            author_names,
            package_description,
            template_name,
        )
        files[MARKER_PATH] = JSON3.write(Dict("version" => 1, "fingerprint" => fingerprint,
            "state" => "files_committed", "project_sha256" => bytes2hex(SHA.sha256(files["Project.toml"]))))
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

    stage[] = "default_branch"
    _ensure_main_branch(
        access_token,
        owner_name,
        repo_name,
        default_branch,
        commit_sha;
        requester = requester,
    )
    if template_name != "minimum"
        stage[] = "documentation"
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
        stage[] = "coverage_secret"
        _set_repository_secret(
            access_token,
            owner_name,
            repo_name,
            "CODECOV_TOKEN",
            String(codecov_token);
            requester = requester,
        )
    end

    stage[] = "completion_record"
    marker = _marker(access_token, owner_name, repo_name; requester)
    isnothing(marker) && throw(InputError("Recovery marker is missing."))
    marker.data["state"] = "complete"
    _request_json("PUT", "$GITHUB_API_URL/repos/$owner_name/$repo_name/contents/$MARKER_PATH";
        token=access_token, body=Dict("message" => "Record completed PkgFactory setup",
            "content" => Base64.base64encode(JSON3.write(marker.data)), "sha" => marker.sha), requester)
    return Dict(
        "repository" => "$(owner_name)/$(repo_name)",
        "url" => "https://github.com/$(owner_name)/$(repo_name)",
        "resumed" => repository_status == 200,
    )
end

"""Create a package with process-local exclusion for the target repository.
Use one serving process; separate processes require an external operation lock.
"""
function create_package(token::AbstractString, owner::String, repo::String,
    authors::Vector{String}, description::String, codecov_token::AbstractString=""; kwargs...)
    _validate_owner(owner)
    _bounded_text(repo, "package_name", 100)
    stage = Ref("validation")
    _with_repository_lock(owner, _normalize_repo_name(repo)) do
        try
            _create_package(token, owner, repo, authors, description, codecov_token; stage, kwargs...)
        catch err
            err isa InterruptException && rethrow()
            err isa InputError && rethrow()
            stage[] == "validation" && rethrow()
            throw(CreationError(stage[], err isa GitHubAPIError ? err.status : 500))
        end
    end
end

end

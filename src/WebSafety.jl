# Included inside WebAPI. No credentials are retained in shared state.
struct InputError <: Exception
    message::String
end
Base.showerror(io::IO, err::InputError) = print(io, err.message)

struct CreationError <: Exception
    stage::String
    status::Int
end
Base.showerror(io::IO, err::CreationError) = print(io,
    "Package creation stopped at ", err.stage,
    ". GitHub may have changed; check repository status before resuming.")

"""Bounded GitHub transport. Writes are never automatically retried or redirected."""
struct GitHubTransport{F}
    request::F
    connect_timeout::Int
    read_timeout::Int
end
function GitHubTransport(; request=HTTP.request, connect_timeout=10, read_timeout=30)
    connect_timeout > 0 && read_timeout > 0 || throw(ArgumentError("Timeouts must be positive"))
    GitHubTransport(request, Int(connect_timeout), Int(read_timeout))
end
function (transport::GitHubTransport)(method, url; kwargs...)
    transport.request(method, url; connect_timeout=transport.connect_timeout,
        readtimeout=transport.read_timeout, retry=false, redirect=false, kwargs...)
end

function _bounded_text(value, field, limit; empty=false)
    value isa AbstractString || throw(InputError("$field must be a string."))
    (empty || !isempty(strip(value))) && ncodeunits(value) <= limit ||
        throw(InputError("$field has an invalid length."))
    return String(value)
end

function _validate_owner(owner)
    _bounded_text(owner, "owner", 100)
    # Validate URL path components without imposing rules on GitHub account types.
    occursin(r"^[A-Za-z0-9][A-Za-z0-9-]*$", owner) ||
        throw(InputError("owner must contain only ASCII letters, digits and hyphens."))
end

const ACTIVE_REPOSITORIES = Set{String}()
const REPOSITORY_MUTEX = ReentrantLock()
function _with_repository_lock(f, owner, repo)
    key = lowercase("$owner/$repo")
    lock(REPOSITORY_MUTEX) do
        key in ACTIVE_REPOSITORIES && throw(GitHubAPIError(409, "Repository operation already in progress."))
        length(ACTIVE_REPOSITORIES) < 8 || throw(GitHubAPIError(429, "Creation capacity reached."))
        push!(ACTIVE_REPOSITORIES, key)
    end
    try
        f()
    finally
        lock(REPOSITORY_MUTEX) do
            delete!(ACTIVE_REPOSITORIES, key)
        end
    end
end

const MARKER_PATH = ".pkgfactory.json"
function _fingerprint(owner, repo, authors, description, template, visibility, message)
    bytes2hex(SHA.sha256(JSON3.write([lowercase(owner), lowercase(repo), authors,
        description, template, visibility, message])))
end

function _marker(token, owner, repo; requester=GitHubTransport())
    file, status = _request_json("GET", "$GITHUB_API_URL/repos/$owner/$repo/contents/$MARKER_PATH";
        token, expected=(200, 404), requester)
    status == 404 && return nothing
    data = try
        JSON3.read(String(Base64.base64decode(replace(file["content"], r"\s" => ""))), Dict{String,Any})
    catch
        throw(InputError("Invalid PkgFactory recovery marker. Inspect the repository manually."))
    end
    get(data, "version", nothing) == 1 || throw(InputError("Unsupported recovery marker."))
    return (data=data, sha=String(file["sha"]))
end

"""Inspect GitHub recovery state without modifying the repository or storing a token."""
function repository_status(token::AbstractString, owner::String, repo::String; requester=GitHubTransport())
    _validate_owner(owner)
    _bounded_text(repo, "package_name", 100)
    Verifications.verify_package_name(_package_name(repo)) == "OK" || throw(InputError("Invalid package name."))
    repo = _normalize_repo_name(repo)
    _, status = _repository(token, owner, repo; requester)
    status == 404 && return Dict("repository" => "$owner/$repo", "state" => "not_found")
    marker = _marker(token, owner, repo; requester)
    state = isnothing(marker) ? "unverified" : get(marker.data, "state", "unverified")
    state in ("files_committed", "complete") || (state = "unverified")
    return Dict("repository" => "$owner/$repo", "state" => state)
end

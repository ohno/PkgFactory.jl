"""Browser-based interface and local HTTP server for PkgFactory."""
module WebUI

import DocStringExtensions
import HTTP
import JSON3
import Sockets

import ..Templates
import ..WebAPI

const WEB_ROOT = normpath(joinpath(@__DIR__, "web"))
const LOGO_PATH = normpath(joinpath(@__DIR__, "..", "docs", "src", "assets", "logo.svg"))

hello() = "Hello, WebUI.jl!"

function _asset(name::String)::String
    path = normpath(joinpath(WEB_ROOT, name))
    startswith(path, WEB_ROOT) || error("Invalid asset path.")
    return read(path, String)
end

function _response(
    status::Int,
    body::AbstractString;
    content_type::String = "text/plain; charset=utf-8",
)
    headers = [
        "Content-Type" => content_type,
        "Cache-Control" => "no-store",
        "X-Content-Type-Options" => "nosniff",
        "Referrer-Policy" => "no-referrer",
        "X-Frame-Options" => "DENY",
    ]
    return HTTP.Response(status, headers, body)
end

_json_response(status::Int, body) =
    _response(status, JSON3.write(body); content_type = "application/json; charset=utf-8")

function _json_body(request::HTTP.Request)::Dict{String,Any}
    isempty(request.body) && return Dict{String,Any}()
    try
        return JSON3.read(String(request.body), Dict{String,Any})
    catch
        throw(WebAPI.InputError("The request body must be a JSON object."))
    end
end

function _access_token(request::HTTP.Request)::String
    authorization = HTTP.header(request, "Authorization", "")
    startswith(authorization, "Bearer ") || throw(RequestError(401, "GitHub authentication is required."))
    token = strip(authorization[8:end])
    isempty(token) && throw(RequestError(401, "GitHub authentication is required."))
    ncodeunits(token) <= 4096 || throw(RequestError(401, "Invalid authentication."))
    return String(token)
end

function _route(request::HTTP.Request)::Tuple{String,String}
    target = split(String(request.target), '?'; limit = 2)[1]
    return String(request.method), target
end

include("WebPolicy.jl")

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Handle one browser or API request. The GitHub requester and key generator are
injectable so the complete workflow can be tested without network access.
"""
function handle_request(
    request::HTTP.Request;
    client_id::String = WebAPI.GITHUB_OAUTH_CLIENT_ID,
    requester = WebAPI.GitHubTransport(),
    key_generator = WebAPI._generate_keys,
    policy = DEFAULT_POLICY,
    client_ip = "local",
)
    method, path = _route(request)
    try
        _guard_request(request, policy, client_ip)
        if method == "GET" && path == "/"
            response = _response(
                200,
                _asset("index.html");
                content_type = "text/html; charset=utf-8",
            )
            push!(
                response.headers,
                "Content-Security-Policy" =>
                    "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
            )
            return response
        elseif method == "GET" && path in ("/app.js", "/assets/app.js")
            return _response(
                200,
                _asset("app.js");
                content_type = "text/javascript; charset=utf-8",
            )
        elseif method == "GET" && path in ("/style.css", "/assets/style.css")
            return _response(
                200,
                _asset("style.css");
                content_type = "text/css; charset=utf-8",
            )
        elseif method == "GET" && path == "/assets/logo.svg"
            return _response(
                200,
                read(LOGO_PATH, String);
                content_type = "image/svg+xml; charset=utf-8",
            )
        elseif method == "GET" && path == "/api/health"
            return _json_response(200, Dict("status" => "ok"))
        elseif method == "GET" && path == "/api/config"
            return _json_response(
                200,
                Dict(
                    "client_id" => client_id,
                    "templates" => Templates.list_templates(),
                ),
            )
        elseif method == "POST" && path == "/api/oauth/device"
            _fields(_json_body(request), String[])
            result = WebAPI.device_flow_begin(client_id; requester = requester)
            return _json_response(200, result)
        elseif method == "POST" && path == "/api/oauth/token"
            body = _json_body(request)
            _fields(body, ["device_code"], ["device_code"])
            device_code = WebAPI._bounded_text(body["device_code"], "device_code", 1024)
            result = WebAPI.device_flow_poll(
                device_code,
                client_id;
                requester = requester,
            )
            return _json_response(200, result)
        elseif method == "GET" && path == "/api/github/owners"
            owners = WebAPI.get_repository_owners(
                _access_token(request);
                requester = requester,
            )
            return _json_response(200, Dict("owners" => owners))
        elseif method == "POST" && path in ("/api/github/repository-availability", "/api/github/repository-status")
            access_token = _access_token(request)
            body = _json_body(request)
            _fields(body, ["owner", "package_name"], ["owner", "package_name"])
            WebAPI._bounded_text(body["owner"], "owner", 100)
            WebAPI._bounded_text(body["package_name"], "package_name", 100)
            lookup = endswith(path, "repository-status") ? WebAPI.repository_status : WebAPI.repository_availability
            result = lookup(
                access_token,
                String(get(body, "owner", "")),
                String(get(body, "package_name", ""));
                requester = requester,
            )
            return _json_response(200, result)
        elseif method == "POST" && path == "/api/packages"
            access_token = _access_token(request)
            body = _package_body(request)
            authors = String.(body["authors"])
            result = WebAPI.create_package(
                access_token,
                String(get(body, "owner", "")),
                String(get(body, "package_name", "")),
                authors,
                String(get(body, "description", "")),
                String(get(body, "codecov_token", ""));
                template_name = String(get(body, "template", "all-in-one")),
                visibility = String(get(body, "visibility", "public")),
                commit_message = String(
                    get(body, "commit_message", "Using PkgFactory.jl"),
                ),
                resume = Bool(get(body, "resume", false)),
                requester = requester,
                key_generator = key_generator,
            )
            return _json_response(201, result)
        end
        return _json_response(404, Dict("error" => "Not found."))
    catch error
        return _error_response(error)
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Start the local web interface. The default host accepts connections only from
the current computer.

```julia
PkgFactory.WebUI.start()
```
"""
function start(
    host::AbstractString = get(ENV, "HOST", "127.0.0.1"),
    port::Integer = parse(Int, get(ENV, "PORT", "8000"));
    verbose::Bool = false,
    public_origin::AbstractString = get(ENV, "PUBLIC_ORIGIN", "http://$(host):$(port)"),
    max_body_bytes::Integer = 65536,
    trusted_proxies = String[],
    client_id::String = get(ENV, "GITHUB_OAUTH_CLIENT_ID", WebAPI.GITHUB_OAUTH_CLIENT_ID),
    requester = WebAPI.GitHubTransport(),
)
    @info "PkgFactory Web UI is available at http://$(host):$(port)/"
    policy = WebPolicy(; public_origin, max_body_bytes)
    handler = (request; kwargs...) -> handle_request(request; client_id, requester, kwargs...)
    return HTTP.serve!(
        stream -> _serve_stream(stream, policy, handler, trusted_proxies),
        String(host),
        Int(port);
        verbose = verbose,
        stream = true,
        readtimeout = 60,
        max_connections = 128,
    )
end

end

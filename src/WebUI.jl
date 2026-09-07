"""Browser-based interface and local HTTP server for PkgFactory."""
module WebUI

import DocStringExtensions
import HTTP
import JSON3

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
        error("The request body must be valid JSON.")
    end
end

function _access_token(request::HTTP.Request)::String
    authorization = HTTP.header(request, "Authorization", "")
    startswith(authorization, "Bearer ") || error("GitHub authentication is required.")
    token = strip(authorization[8:end])
    isempty(token) && error("GitHub authentication is required.")
    return token
end

function _route(request::HTTP.Request)::Tuple{String,String}
    target = split(String(request.target), '?'; limit = 2)[1]
    return String(request.method), target
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

Handle one browser or API request. The GitHub requester and key generator are
injectable so the complete workflow can be tested without network access.
"""
function handle_request(
    request::HTTP.Request;
    client_id::String = WebAPI.GITHUB_OAUTH_CLIENT_ID,
    requester = HTTP.request,
    key_generator = WebAPI._generate_keys,
)
    method, path = _route(request)
    try
        if method == "GET" && path == "/"
            response = _response(
                200,
                _asset("index.html");
                content_type = "text/html; charset=utf-8",
            )
            push!(
                response.headers,
                "Content-Security-Policy" =>
                    "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'self'",
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
            result = WebAPI.device_flow_begin(client_id; requester = requester)
            return _json_response(200, result)
        elseif method == "POST" && path == "/api/oauth/token"
            body = _json_body(request)
            device_code = String(get(body, "device_code", ""))
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
        elseif method == "POST" && path == "/api/github/repository-availability"
            access_token = _access_token(request)
            body = _json_body(request)
            result = WebAPI.repository_availability(
                access_token,
                String(get(body, "owner", "")),
                String(get(body, "package_name", ""));
                requester = requester,
            )
            return _json_response(200, result)
        elseif method == "POST" && path == "/api/packages"
            access_token = _access_token(request)
            body = _json_body(request)
            authors = String.(get(body, "authors", Any[]))
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
        status = error isa WebAPI.GitHubAPIError ? error.status : 400
        return _json_response(status, Dict("error" => sprint(showerror, error)))
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
)
    @info "PkgFactory Web UI is available at http://$(host):$(port)/"
    return HTTP.serve!(
        request -> handle_request(request),
        String(host),
        Int(port);
        verbose = verbose,
    )
end

end

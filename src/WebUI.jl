"""
This module contains the GUI on a web browser.
"""
module WebUI

# Packages

import HTTP
import JSON3
import DocStringExtensions
import Dates
# import Oxygen

function hello()
    return "Hello, World!2"
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

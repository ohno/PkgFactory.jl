module PkgFactory

function hello()
    return "Hello, PkgFactory.jl!"
end

include("Verifications.jl")
include("Templates.jl")
include("LocalAPI.jl")

end

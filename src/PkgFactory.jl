module PkgFactory

import DocStringExtensions

function hello()
    return "Hello, PkgFactory.jl!"
end

include("Verifications.jl")
include("Templates.jl")
include("LocalAPI.jl")
include("LocalUI.jl")
include("WebAPI.jl")
include("WebUI.jl")
include("NotebookAPI.jl")

end

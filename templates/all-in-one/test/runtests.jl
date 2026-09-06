using {{{PKG}}}
using Test

include("aqua.jl")

@static if get(ENV, "JET_TEST", "true") == "true"
    include("jet.jl")
end

@testset "{{{PKG}}}.hello" begin
    @test {{{PKG}}}.hello() == "Hello, World!"
end

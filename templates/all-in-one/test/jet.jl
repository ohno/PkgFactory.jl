using {{{PKG}}}
using JET
using Test

@testset "JET.jl" begin
    JET.test_package({{{PKG}}}; target_modules = ({{{PKG}}},))
end

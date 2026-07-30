using {{{PKG}}}
using Aqua
using JET
using Test

@testset "Aqua.jl" begin
    Aqua.test_all({{{PKG}}})
end

@testset "JET.jl" begin
    JET.test_package({{{PKG}}}; target_modules = ({{{PKG}}},))
end

@testset "{{{PKG}}}.hello" begin
    @test {{{PKG}}}.hello() == "Hello, World!"
end

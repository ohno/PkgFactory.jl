using {{{PKG}}}
using Aqua
using Test

@testset "Aqua.jl" begin
    Aqua.test_all({{{PKG}}})
end

@static if get(ENV, "JET_TEST", "true") == "true"
    import JET

    @testset "JET.jl" begin
        JET.test_package({{{PKG}}}; target_modules = ({{{PKG}}},))
    end
end

@testset "{{{PKG}}}.hello" begin
    @test {{{PKG}}}.hello() == "Hello, World!"
end

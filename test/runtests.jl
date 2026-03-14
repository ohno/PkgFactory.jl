using PkgFactory
using Test

@testset "PkgFactory.check_status_code" begin
    @test PkgFactory.check_status_code()
end

@testset "PkgFactory.verify_package_name" begin
    @test "OK" == PkgFactory.verify_package_name("Physics")
    @test "OK" != PkgFactory.verify_package_name("")
    @test "OK" != PkgFactory.verify_package_name("JuliaPkg")
    @test "OK" != PkgFactory.verify_package_name("JustInTime")
    @test "OK" != PkgFactory.verify_package_name("algebra")
    @test "OK" != PkgFactory.verify_package_name("Linear_algebra")
    @test "OK" != PkgFactory.verify_package_name("Math+Physics")
    @test "OK" != PkgFactory.verify_package_name("algebra")
    @test "OK" != PkgFactory.verify_package_name("Eigen京")
    @test "OK" != PkgFactory.verify_package_name("VMC")
    @test "OK" != PkgFactory.verify_package_name("Cake")
    @test "OK" != PkgFactory.verify_package_name("juliaCI")
    @test "OK" != PkgFactory.verify_package_name("Jump")
    @test "OK" != PkgFactory.verify_package_name("VMCjl")
    @test "OK" != PkgFactory.verify_package_name("VMC.jl")
    @test "OK" != PkgFactory.verify_package_name("Eigen京")
end

@testset "JLL executable paths" begin
    @test !isempty(PkgFactory.git_executable())
    @test !isempty(PkgFactory.gh_executable())
end

using PkgFactory
using Test

@testset "hello" begin
    @test occursin("Hello", PkgFactory.hello())
    @test occursin("Hello", PkgFactory.Verifications.hello())
    @test occursin("Hello", PkgFactory.Templates.hello())
    @test occursin("Hello", PkgFactory.LocalAPI.hello())
end

@testset "verify_owner_name" begin
    @test "OK" == PkgFactory.Verifications.verify_owner_name("ohno")
    @test "OK" != PkgFactory.Verifications.verify_owner_name("")
end

@testset "verify_package_name" begin
    @test "OK" == PkgFactory.Verifications.verify_package_name("Physics")
    @test "OK" != PkgFactory.Verifications.verify_package_name("")
    @test "OK" != PkgFactory.Verifications.verify_package_name("JuliaPkg")
    @test "OK" != PkgFactory.Verifications.verify_package_name("JustInTime")
    @test "OK" != PkgFactory.Verifications.verify_package_name("algebra")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Linear_algebra")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Math+Physics")
    @test "OK" != PkgFactory.Verifications.verify_package_name("algebra")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Eigen京")
    @test "OK" != PkgFactory.Verifications.verify_package_name("VMC")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Cake")
    @test "OK" != PkgFactory.Verifications.verify_package_name("juliaCI")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Jump")
    @test "OK" != PkgFactory.Verifications.verify_package_name("VMCjl")
    @test "OK" != PkgFactory.Verifications.verify_package_name("VMC.jl")
    @test "OK" != PkgFactory.Verifications.verify_package_name("Eigen京")
end

@testset "get_template_path" begin
    path_dir = PkgFactory.Templates.get_template_path("all-in-one")
    @test isdir(path_dir)
    @test occursin("all-in-one", path_dir)    
end

@testset "list_files" begin
    path_dir = PkgFactory.Templates.get_template_path("all-in-one")
    path_files = PkgFactory.Templates.list_files(path_dir)
    @test 0 < length(path_files)
    @test 0 < sum(occursin("README.md", path_file) for path_file in path_files)
    @test 0 < sum(occursin("LICENSE", path_file) for path_file in path_files)
    @test 0 == sum(occursin("aaaaa", path_file) for path_file in path_files)    
end

@testset "read_file" begin
    path_dir   = PkgFactory.Templates.get_template_path("all-in-one")
    path_files = PkgFactory.Templates.list_files(path_dir)
    path_file  = path_files[findfirst(occursin("README.md", path_file) for path_file in path_files)]
    text = PkgFactory.Templates.read_file(path_file)
    @test 0 < length(path_file)
    @test occursin("README.md", path_file)    
    @test 0 < length(text)
    @test occursin(".jl", path_file)    
end

@testset "generate_template_files_dict" begin
    owner_name = "ohno"
    repo_name = "MyPkg.jl"
    author_names = ["Shuhei Ohno"]
    package_description = "My special package"
    template_name = "all-in-one"
    paths_and_contents = PkgFactory.Templates.generate_template_files_dict(owner_name, repo_name, author_names, package_description, template_name)
    @test 0 < length(paths_and_contents)
    @test 0 < length(paths_and_contents["README.md"])
    @test occursin("MyPkg.jl", paths_and_contents["README.md"])
    @test occursin("Shuhei Ohno", paths_and_contents["LICENSE"])
    @test occursin("My special package", paths_and_contents["README.md"])
end

# @testset "PkgFactory.check_status_code" begin
#     @test PkgFactory.check_status_code()
# end


# @testset "JLL executable paths" begin
#     @test !isempty(PkgFactory.git_executable())
#     @test !isempty(PkgFactory.gh_executable())
# end

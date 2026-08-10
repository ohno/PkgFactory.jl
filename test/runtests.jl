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

@testset "generated template contracts" begin
    render(template_name) = PkgFactory.Templates.generate_template_files_dict(
        "ohno",
        "MyPkg.jl",
        ["Shuhei Ohno"],
        "My special package",
        template_name,
    )

    all_in_one = render("all-in-one")
    minimum = render("minimum")

    @test haskey(all_in_one, "src/MyPkg.jl")
    @test haskey(minimum, "src/MyPkg.jl")
    @test occursin("version = \"0.0.1\"", all_in_one["Project.toml"])
    @test occursin("version = {v0.0.1}", all_in_one["CITATION.bib"])
    project_uuid = only(match(r"uuid = \"([^\"]+)\"", all_in_one["Project.toml"]).captures)
    @test occursin("MyPkg = \"$(project_uuid)\"", all_in_one["docs/Project.toml"])

    @test !occursin("[extras]", all_in_one["Project.toml"])
    @test !occursin("[targets]", all_in_one["Project.toml"])
    @test !occursin("Aqua =", all_in_one["Project.toml"])
    @test !occursin("JET =", all_in_one["Project.toml"])
    @test !occursin("Test =", all_in_one["Project.toml"])
    @test occursin("julia = \"1.10\"", all_in_one["Project.toml"])
    @test occursin("Aqua =", all_in_one["test/Project.toml"])
    @test occursin("JET = \"0.9, 0.10, 0.11, 0.12\"", all_in_one["test/Project.toml"])
    @test occursin("Test =", all_in_one["test/Project.toml"])
    @test occursin("Documenter = \"1\"", all_in_one["docs/Project.toml"])

    @test !haskey(all_in_one, ".github/workflows/CompatHelper.yml")
    dependabot = all_in_one[".github/dependabot.yml"]
    @test occursin("package-ecosystem: \"github-actions\"", dependabot)
    @test occursin("package-ecosystem: \"julia\"", dependabot)
    for directory in ("/", "/docs", "/test")
        @test occursin("- \"$(directory)\"", dependabot)
    end

    all_ci = all_in_one[".github/workflows/CI.yml"]
    @test occursin(raw"${{ matrix.version }}", all_ci)
    @test occursin("version: 'min'", all_ci)
    @test count(==(true), occursin.("coverage: true", eachline(IOBuffer(all_ci)))) == 1
    @test count(==(true), occursin.("jet: 'true'", eachline(IOBuffer(all_ci)))) == 1
    @test occursin("version: 'pre'", all_ci)
    @test occursin("continue-on-error:", all_ci)
    @test occursin("JET_TEST:", all_ci)
    @test occursin("@static if get(ENV, \"JET_TEST\", \"true\") == \"true\"", all_in_one["test/runtests.jl"])

    @test occursin("```jldoctest", all_in_one["src/MyPkg.jl"])
    @test occursin("MyPkg.hello()", all_in_one["src/MyPkg.jl"])
    @test occursin("Return a friendly greeting.", all_in_one["src/MyPkg.jl"])
    @test !occursin("hello()::String", all_in_one["src/MyPkg.jl"])
    @test !occursin("#L", all_in_one["docs/src/developer.md"])
    @test occursin("[ColPrac version increment guidelines]", all_in_one["docs/src/developer.md"])
    @test !occursin("```@index", all_in_one["docs/src/index.md"])
    @test occursin("import MyPkg # hide", all_in_one["docs/src/index.md"])
    @test occursin("pkgdir(MyPkg)", all_in_one["docs/src/index.md"])
    @test !occursin("../../CITATION.bib", all_in_one["docs/src/index.md"])
    @test occursin(r"month\s+= \{[a-z]{3}\}", all_in_one["CITATION.bib"])
    @test occursin("# Paste the complete output here.", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])
    @test !occursin("8fce2d05", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])
    @test !occursin("Julia Version 1.10.10", all_in_one[".github/ISSUE_TEMPLATE/bug_report.md"])

    @test haskey(minimum, ".github/workflows/CI.yml")
    @test occursin("actions/workflows/CI.yml/badge.svg", minimum["README.md"])
    @test occursin("Pkg.add(url=", minimum["README.md"])
    @test occursin("MyPkg.hello()", minimum["README.md"])
    @test occursin(raw"${{ matrix.version }}", minimum[".github/workflows/CI.yml"])
    @test occursin("version: 'min'", minimum[".github/workflows/CI.yml"])
    @test occursin("version: 'pre'", minimum[".github/workflows/CI.yml"])
    @test !occursin("[extras]", minimum["Project.toml"])
    @test !occursin("[targets]", minimum["Project.toml"])
    @test occursin("julia = \"1.10\"", minimum["Project.toml"])
    @test occursin("Test =", minimum["test/Project.toml"])
    @test !any(startswith(path, "docs/") for path in keys(minimum))
    @test !haskey(minimum, "CITATION.bib")
    @test !occursin("CITATION", minimum["README.md"])
    @test !occursin("Documentation", minimum["README.md"])
    @test !any(
        occursin(dependency, content) for
            dependency in ("Documenter", "Codecov", "JET") for
            content in values(minimum)
    )
end

# @testset "PkgFactory.check_status_code" begin
#     @test PkgFactory.check_status_code()
# end


# @testset "JLL executable paths" begin
#     @test !isempty(PkgFactory.git_executable())
#     @test !isempty(PkgFactory.gh_executable())
# end

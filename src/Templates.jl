"""
This module contains functions for generating the package from the [templates](https://github.com/ohno/PkgFactory.jl/tree/main/templates) directory using [Mustache.jl](https://github.com/jverzani/Mustache.jl).
"""
module Templates

# Packages

import DocStringExtensions
import PkgTemplates
import Mustache
import UUIDs
import Dates

function hello()
    return "Hello, Templates.jl"
end

# Functions

function _get_templates_path()::String
    return normpath(joinpath(@__DIR__, "..", "templates"))
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
path_dir = PkgFactory.Templates.get_template_path("all-in-one")
```
"""
function get_template_path(template_name::String)
    return normpath(joinpath(_get_templates_path(), template_name))
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
template_names = PkgFactory.Templates.list_templates()
```
"""
function list_templates()::Vector{String}
    templates_path = _get_templates_path()
    return sort(
        filter(name -> isdir(joinpath(templates_path, name)), readdir(templates_path)),
    )
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
path_dir = PkgFactory.Templates.get_template_path("all-in-one")
path_files = PkgFactory.Templates.list_files(path_dir)
```
"""
function list_files(template_path::String)::Vector{String}
    return sort([joinpath(dir, f) for (dir, _, fs) in walkdir(template_path) for f in fs])
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
path_dir   = PkgFactory.Templates.get_template_path("all-in-one")
path_files = PkgFactory.Templates.list_files(path_dir)
path_file  = path_files[findfirst(occursin("README.md", path_file) for path_file in path_files)]
text = PkgFactory.Templates.read_file(path_file)
```
"""
function read_file(path::String)::String
    try
        text = Base.read(path, String)
        @info "Success to read file: $(path)"
        return text
    catch e
        @error "Failed to read file: $(path)" exception = (e, catch_backtrace())
        rethrow()
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
path_dir   = PkgFactory.Templates.get_template_path("all-in-one")
path_files = PkgFactory.Templates.list_files(path_dir)
path_file  = path_files[findfirst(occursin("README.md", path_file) for path_file in path_files)]
text = PkgFactory.Templates.read_file(path_file)
```
"""
function write_file(path::String, content::String)
    try
        Base.write(path, content)
        @info "write_file: $(path)"
        return true
    catch e
        @error "Failed to write file: $(path)" exception = (e, catch_backtrace())
        rethrow()
    end
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
paths_and_contents = PkgFactory.Templates.generate_template_files_dict(
  "ohno",
  "MyPkg.jl",
  ["Shuhei Ohno"],
  "My special package",
  "all-in-one"
)
```
"""
function generate_template_files_dict(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
    package_description::String,
    template_name::String;
    package_uuid::Union{Nothing,String} = nothing,
)::Dict{String,String}

    package_name = replace(repo_name, r"\.jl$" => "")
    ctx = Dict(
        "PKG" => package_name,
        "REPO" => repo_name,
        "OWNER" => owner_name,
        "DESCR" => package_description,
        "UUID" => isnothing(package_uuid) ? string(UUIDs.uuid4()) : package_uuid,
        "AUTHORS" => author_names,
        "LICENSOR" => join(author_names, ", "),
        "URL" => "https://github.com/$(owner_name)/$(repo_name)",
        "VERSION" => "v0.0.1",
        "YEAR" => Dates.year(Dates.today()),
        "MONTH" => lowercase(Dates.monthabbr(Dates.today())),
    )

    paths_and_contents = Dict{String,String}()

    path_dir = get_template_path(template_name)
    path_files = list_files(path_dir)
    for path_file in path_files
        # key
        key = relpath(path_file, path_dir)
        key = replace(key, "\\" => "/")
        if key == "src/PKG.jl"
            key = "src/$(ctx["PKG"]).jl"
        end
        # content
        text = read_file(path_file)
        rendered = if endswith(key, ".yml") && !endswith(key, "CI.yml")
            text
        else
            Mustache.render(text, ctx)
        end
        # 
        paths_and_contents[key] = rendered
    end

    return paths_and_contents

end

"""
!!! warning
    This function is only for developers. This function updates the template files in the `PkgFactory.jl/template` directory.

Signature:

$(DocStringExtensions.TYPEDSIGNATURES)

Example:

```julia
PkgFactory.update_template("OWNER_NAME", "template", ["AUTHOR1", "AUTHOR2"])
```
"""
function update_template(
    owner_name::String,
    repo_name::String,
    author_names::Vector{String},
)::Dict{String,String}
    template = PkgTemplates.Template(;
        dir = "$(@__DIR__)/../",
        user = owner_name,
        authors = author_names,
        julia = v"1.10",
        plugins = [
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Default-Plugins
            PkgTemplates.ProjectFile(; version = v"0.0.1"),
            PkgTemplates.SrcDir(),
            PkgTemplates.Tests(; project = true),
            PkgTemplates.Readme(),
            PkgTemplates.License(),
            # PkgTemplates.Git(; ignore = ["*/Manifest.toml"]),
            PkgTemplates.GitHubActions(; extra_versions = ["1.10"]),
            PkgTemplates.TagBot(),
            # PkgTemplates.Secret(),
            PkgTemplates.Dependabot(),
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Code-Coverage
            PkgTemplates.Codecov(),
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Documentation
            PkgTemplates.Documenter{PkgTemplates.GitHubActions}(),
            # https://juliaci.github.io/PkgTemplates.jl/stable/user/#Miscellaneous
            PkgTemplates.Citation(; readme = true),
            # PkgTemplates.Formatter(),
        ],
    )
    return template(repo_name)
end

end

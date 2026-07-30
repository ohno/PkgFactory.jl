"""
This module contains functions for generating the package from [templates](../template) directory using [Mustache.jl](https://github.com/jverzani/Mustache.jl).
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

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
path_dir = PkgFactory.Templates.get_template_path("all-in-one")
```
"""
function get_template_path(template_name::String)
    return normpath("$(@__DIR__)/../templates/$(template_name)/")
end

"""
$(DocStringExtensions.TYPEDSIGNATURES)

```
path_dir = PkgFactory.Templates.get_template_path("all-in-one")
path_files = PkgFactory.Templates.list_files(path_dir)
```
"""
function list_files(template_path::String)::Vector{String}
    return [joinpath(dir, f) for (dir, _, fs) in walkdir(template_path) for f in fs]
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
        Base.read(path, String)
        @info "Success to read file: $(path)"
        
        return text
    catch
        @info "Failed to read file: $(path)"
        return ""
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
    catch
        @info "Failed to write file: $(path)"
        return error("Failed to write file: $(path)")
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
function generate_template_files_dict(owner_name::String, repo_name::String, author_names::Vector{String}, package_description::String, template_name::String)::Dict{String, String}

    ctx = Dict(
        "PKG"      => replace(repo_name, ".jl" => ""),
        "REPO"     => repo_name,
        "OWNER"    => owner_name,
        "DESCR"    => package_description,
        "UUID"     => string(UUIDs.uuid4()),
        "AUTHORS"  => author_names,
        "LICENSOR" => join(author_names, ", "),
        "URL"      => "https://github.com/$(owner_name)/$(repo_name)",
        "VERSION"  => "v0.0.1",
        "YEAR"     => Dates.year(Dates.today()),
        "MONTH"    => Dates.month(Dates.today()),
    )

    paths_and_contents = Dict{String, String}()

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
        rendered = if key[end-3:end] == ".yml" && key[end-5:end] != "CI.yml"
            text
        else
            Mustache.render(text, ctx)
        end
        # 
        paths_and_contents[key] = rendered
    end
    
    return paths_and_contents

end

end

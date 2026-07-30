"""
This module contains functions for verifying the package name and other inputs.
"""
module Verifications

# Packages

import DocStringExtensions

function hello()
    return "Hello, Verifications.jl!"
end

# Functions

"""
This function verifies the owner name according to the [GitHub username rules](https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/iam-configuration-reference/username-considerations-for-external-authentication#about-username-normalization).

Usernames for user accounts on GitHub can only contain alphanumeric characters and dashes (-).

$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.Verifications.verify_owner_name("ohno")
```
"""
function verify_owner_name(owner_name::String)
    # https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/iam-configuration-reference/username-considerations-for-external-authentication
    # https://docs.github.com/en/rest/users/users?apiVersion=2026-03-10
    if isempty(owner_name)
        return "The owner name, \"$(owner_name)\" must not be empty."
    end
    return "OK"
end

"""
This function verifies the package name according to the [package naming rules](https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules) of [Pkg.jl](https://github.com/JuliaLang/Pkg.jl) and the [automatic merging guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) of [RegistryCI.jl](https://github.com/JuliaRegistries/RegistryCI.jl).

$(DocStringExtensions.TYPEDSIGNATURES)

```
PkgFactory.Verifications.verify_package_name("MyPkg")
```
"""
function verify_package_name(package_name::String)

    # Guidelines
    url_1 = "https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules"
    url_2 = "https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/"

    if isempty(package_name)
        return "The package name, \"$(package_name)\" must not be empty."
    end

    # https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules
    # 1. Avoid jargon. In particular, avoid acronyms unless there is minimal possibility of confusion.
    # 2. Avoid using Julia in your package name or prefixing it with Ju.

    if occursin("Julia", package_name)
        return "The package name, \"$(package_name)\" must not contain 'Julia'. See $(url_1)."
    end

    if startswith(package_name, "Ju")
        return "The package name, \"$(package_name)\" must not start with 'Ju'. See $(url_1)."
    end

    # 3. Packages that provide most of their functionality in association with a new type should have pluralized names.
    # 4. Err on the side of clarity, even if clarity seems long-winded to you.
    # 5. A less systematic name may suit a package that implements one of several possible approaches to its domain.
    # 6. Packages that wrap external libraries or programs can be named after those libraries or programs.
    # 7. Avoid naming a package closely to an existing package.
    # 8. Avoid using a distinctive name that is already in use in a well known, unrelated project.
    # 9. Packages should follow the Stylistic Conventions.

    if !isuppercase(package_name[1])
        return "The package name, \"$(package_name)\" must begin with a capital letter. See $(url_1)."
    end

    if occursin(r"[_\-]", package_name)
        return "The package name, \"$(package_name)\" must use upper camel case for word separation (no underscores or hyphens). See $(url_1)."
    end

    # https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/
    # 1. The package name, \"$(package_name)\" should be a valid Julia identifier (according to Base.isidentifier).

    if !Base.isidentifier(package_name)
        return "The package name, \"$(package_name)\" is not a valid Julia identifier. See $(url_2)."
    end

    # 2. The package name, \"$(package_name)\" should start with an upper-case letter, contain only ASCII alphanumeric characters, and contain at least one lowercase letter.

    if !isuppercase(package_name[1]) # not evaluated, already checked in the previous guideline
        return "The package name, \"$(package_name)\" must begin with a capital letter. See $(url_2)."
    end

    if !occursin(r"^[a-zA-Z0-9]+$", package_name)
        return "The package name, \"$(package_name)\" must contain only ASCII alphanumeric characters. See $(url_2)."
    end

    if all(isuppercase, package_name)
        return "The package name, \"$(package_name)\" must contain at least one lowercase letter. See $(url_2)."
    end

    # 3. The name is at least 5 characters long.

    if length(package_name) < 5
        return "The package name, \"$(package_name)\" must be at least 5 characters long. See $(url_2)."
    end

    # 4. Name does not include "julia", start with "Ju", or end with "jl".

    if occursin("julia", package_name) # not evaluated
        return "The package name, \"$(package_name)\" must not include 'julia'. See $(url_2)."
    end

    if startswith(package_name, "Ju") # not evaluated
        return "The package name, \"$(package_name)\" must not start with 'Ju'. See $(url_2)."
    end

    if endswith(package_name, "jl")
        return "The package name, \"$(package_name)\" must not end with 'jl'. See $(url_2)."
    end

    # 5. Repo URL ends with /PackageName.jl.git.

    if endswith(package_name, ".jl") # not evaluated
        return "The package name, \"$(package_name)\" must end with '.jl'. See $(url_2)."
    end

    # 6. Version number is not allowed to contain prerelease data
    # 7. Version number is not allowed to contain build data
    # 8. There is an upper-bounded [compat] entry for julia that only includes a finite number of breaking releases of Julia.
    # 9. Dependencies: All dependencies should have [compat] entries that are upper-bounded and only include a finite number of breaking releases. For more information, please see the "Upper-bounded [compat] entries" subsection under "Additional information" below.
    # 10. Name is composed of ASCII characters only.

    if !all(isascii, package_name) # not evaluated
        return "The package name, \"$(package_name)\" must contain only ASCII alphanumeric characters. See $(url_2)."
    end

    # 11. Package installation: The package should be installable (Pkg.add("PackageName")).
    # 12. Code can be downloaded.
    # 13. License: The package should have an OSI-approved software license located in the top-level directory of the package code, e.g. in a file named LICENSE or LICENSE.md. This check is required for the General registry. For other registries, registry maintainers have the option to disable this check.
    # 14. src files and directories names are OK
    # 15. Package loading: The package should be loadable (import PackageName).
    # 16. Packages must not match the name of existing package up-to-case, since on case-insensitive filesystems, this will break the registry.
    # 17. To prevent confusion between similarly named packages, the names of new packages must also satisfy the following three checks: (for more information, please see the "Name similarity distance check" subsection under "Additional information" below)
    # - the Damerau–Levenshtein distance between the package name and the name of any existing package must be at least 3.
    # - the Damerau–Levenshtein distance between the lowercased version of a package name and the lowercased version of the name of any existing package must be at least 2.
    # - and a visual distance from VisualStringDistances.jl between the package name and any existing package must exceeds a certain a hand-chosen threshold (currently 2.5).

    return "OK"
end

end

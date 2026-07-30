```@meta
CurrentModule = {{{PKG}}}
```

# Developer Guide

If you are planning significant changes, open an [issue](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/issues) first. The [ColPrac](https://github.com/SciML/ColPrac) guidelines are recommended. For Julia package development basics, see:
- [How to develop a Julia package](https://julialang.org/contribute/developing_package/)
- [Pkg: Creating packages](https://pkgdocs.julialang.org/v1/creating-packages/)

## One-Time Local Setup

This procedure is required only once.

1. Clone the [repository](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl).
   ```sh
   git clone https://github.com/{{{OWNER}}}/{{{PKG}}}.jl.git
   cd {{{PKG}}}.jl
   ```
2. Install development tools: [Revise.jl](https://github.com/timholy/Revise.jl) and [Runic.jl](https://github.com/fredrikekre/Runic.jl).
   ```sh
   julia --startup-file=no -e 'import Pkg; Pkg.add("Revise")'
   julia --project=@runic --startup-file=no -e 'using Pkg; Pkg.add("Runic")'
   ```

## Daily Development Flow

This is the typical workflow for making changes.

1. Start an interactive session with [Revise.jl](https://github.com/timholy/Revise.jl).
   ```sh
   cd {{{PKG}}}.jl
   julia --startup-file=no -i -E 'using Revise; import Pkg; Pkg.activate("."); using {{{PKG}}}'
   ```
2. Change the source code:
   - When making new functions or updating docstrings, refer to [Documenter: Adding docstrings](https://documenter.juliadocs.org/stable/man/guide/#Adding-Some-Docstrings).
   - If you need a new dependency, use `julia --project=. --startup-file=no -e 'import Pkg; Pkg.add("SomePackage"); Pkg.resolve(); Pkg.instantiate()'`. Replace `SomePackage` with the actual package name.
3. Format the source code with [Runic.jl](https://github.com/fredrikekre/Runic.jl).
   ```sh
   julia --project=@runic --startup-file=no -e 'using Runic; exit(Runic.main(ARGS))' -- --inplace .
   ```
4. Run the tests.
   ```sh
   julia --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
   ```
5. Build the documentation locally.
   ```sh
   julia --project=docs --startup-file=no -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate();'
   julia --project=docs --startup-file=no -e 'include("docs/make.jl")'
   ```
6. Submit a pull request (after steps 3–5 succeed).

## Versioning and Registering (for Maintainers)

https://github.com/SciML/ColPrac?tab=readme-ov-file#incrementing-the-package-version

This project follows [Semantic Versioning](https://semver.org/). When bumping the version, update the version number in:

- [Project.toml](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/Project.toml#L4)
- [CITATION.bib](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/CITATION.bib#5)

To register this package in the [General](https://github.com/JuliaRegistries/General) registry, install [Registrator](https://github.com/JuliaRegistries/Registrator.jl?tab=readme-ov-file#install-registrator) and use it via the [GitHub App](https://github.com/JuliaRegistries/Registrator.jl?tab=readme-ov-file#via-the-github-app).

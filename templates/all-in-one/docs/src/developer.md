```@meta
CurrentModule = {{{PKG}}}
```

# [Developer Guide](@id developer-guide)

If you are planning significant changes, open an [issue](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/issues) first. The [ColPrac](https://github.com/SciML/ColPrac) guidelines are recommended. For Julia package development basics, see:
- [How to develop a Julia package](https://julialang.org/contribute/developing_package/)
- [Pkg: Creating packages](https://pkgdocs.julialang.org/v1/creating-packages/)

## [One-Time Local Setup](@id local-setup)

This procedure is required only once. Install [Git](https://git-scm.com/) and [Julia](https://julialang.org/install/) on your local machine before starting.

1. Fork the [repository](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl) on GitHub.
2. Clone the forked repository. Replace `xxxxxx` with your GitHub username.
   ```sh
   git clone https://github.com/xxxxxx/{{{PKG}}}.jl.git
   cd {{{PKG}}}.jl
   ```
3. Install development tools: [Revise.jl](https://github.com/timholy/Revise.jl) and [Runic.jl](https://github.com/fredrikekre/Runic.jl).
   ```sh
   julia --startup-file=no -e 'import Pkg; Pkg.add("Revise")'
   julia --project=@runic --startup-file=no -e 'using Pkg; Pkg.add("Runic")'
   ```

## [Daily Development Flow](@id development-flow)

This is the typical workflow for making changes.

1. Create a branch for your changes. Replace `xxx` with the issue number (e.g. `issue/123`).
   ```sh
   cd {{{PKG}}}.jl
   git switch -c issue/xxx
   ```
2. Start an interactive session with [Revise.jl](https://github.com/timholy/Revise.jl).
   ```sh
   julia --startup-file=no -i -e 'using Revise; import Pkg; Pkg.activate("."); using {{{PKG}}}'
   ```
3. Change the source code:
   - When making new functions or updating docstrings, refer to [Documenter: Adding docstrings](https://documenter.juliadocs.org/stable/man/guide/#Adding-Some-Docstrings).
   - If you need a new dependency, use `julia --project=. --startup-file=no -e 'import Pkg; Pkg.add("SomePackage"); Pkg.resolve(); Pkg.instantiate()'`. Replace `SomePackage` with the actual package name.
4. Format the source code with [Runic.jl](https://github.com/fredrikekre/Runic.jl).
   ```sh
   julia --project=@runic --startup-file=no -e 'using Runic; exit(Runic.main(ARGS))' -- --inplace .
   ```
5. Run the tests. It will take a few minutes.
   ```sh
   julia --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
   ```
6. Build the documentation locally. HTML files (`docs/build/*.html`) will be generated. Check them with Chrome or any other web browsers.
   ```sh
   julia --project=docs --startup-file=no -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate();'
   julia --project=docs --startup-file=no -e 'include("docs/make.jl")'
   ```
7. Commit and push the changes (after steps 4–6 succeed).
   ```sh
   git add "path/to/changed/file"
   git commit -m "commit message"
   git push origin issue/xxx
   ```
8. Submit a pull request on GitHub.

## Versioning and Registering (for Maintainers)

This project follows [Semantic Versioning](https://semver.org/) and the [ColPrac version increment guidelines](https://github.com/SciML/ColPrac?tab=readme-ov-file#incrementing-the-package-version). When bumping the version, update:

- the version in [Project.toml](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/Project.toml)
- the version, year, and month in [CITATION.bib](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/CITATION.bib)

Keep the version values synchronized, and set the citation date to the release date.

To register this package in the [General](https://github.com/JuliaRegistries/General) registry, install [Registrator](https://github.com/JuliaRegistries/Registrator.jl?tab=readme-ov-file#install-registrator) and use it via the [GitHub App](https://github.com/JuliaRegistries/Registrator.jl?tab=readme-ov-file#via-the-github-app).

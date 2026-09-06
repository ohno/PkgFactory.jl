# AGENTS.md

## Overview

- PkgFactory.jl generates new Julia packages from templates and bootstraps their GitHub repositories.
- The package name is `PkgFactory` (see Project.toml) regardless of the repository directory name.
- Julia 1.10+ (see `[compat]` in `Project.toml`). Check `.github/workflows/CI.yml` for the versions and platforms actually tested; template CI workflows describe generated packages, not PkgFactory itself.

## Commands

Run all commands from the repository root. Install the project dependencies when setting up a checkout:

```sh
julia --project=. --startup-file=no -e 'import Pkg; Pkg.instantiate()'
```

Run the full test suite:

```sh
julia --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
```

Generate documentation:

```sh
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate();'
julia --project=docs --startup-file=no docs/make.jl
```

`docs/make.jl` calls both `makedocs` and `deploydocs`; CI supplies the deployment credentials. Documentation output is written to `docs/build/`.

Optional development REPL with Revise for quick iteration. Select the project before loading Revise:

```sh
julia --project=. --startup-file=no -i -e 'using Revise; using PkgFactory; PkgFactory.hello()'
```

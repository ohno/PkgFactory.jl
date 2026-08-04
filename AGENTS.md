# AGENTS.md

## Overview

- PkgFactory.jl generates new Julia packages from templates and bootstraps their GitHub repositories.
- The package name is `PkgFactory` (see Project.toml) regardless of the repository directory name.
- Julia 1.10+ (see `[compat]` in Project.toml).

## Commands

Run tests:

```sh
julia --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
```

Generate documentation:

```sh
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate();'
julia --project=docs --startup-file=no -e 'include("docs/make.jl")'
```

Development REPL (with Revise) — use this for quick iteration on a single function; run the full test suite before committing:

```sh
julia -i -E 'using Revise; import Pkg; Pkg.activate("."); using PkgFactory; PkgFactory.hello()'
```

## Structure

- `src/PkgFactory.jl` — top-level module; includes `Verifications.jl` (input validation), `Templates.jl` (package generation from `templates/` via Mustache.jl), and `LocalAPI.jl` (git/GitHub operations via Git.jl and gh_cli_jll, using the user's `gh auth login` session).
- `src/LocalUI.jl`, `src/WebAPI.jl`, `src/WebUI.jl` — WIP, not yet included in `PkgFactory.jl`. The WIP Web API/UI will use the GitHub OAuth device flow (sequence diagram: `docs/src/developer.md`).
- `templates/` — Mustache template sets: `minimum/`, `simple/`, `all-in-one/`.

## Conventions

- Submodules: module docstring → `import` (not `using`) → `hello()` smoke test → documented functions.
- Docstrings use DocStringExtensions (`$(DocStringExtensions.TYPEDSIGNATURES)`) with a usage example.
- `Verifications` functions return `"OK"` on success, an error message otherwise; tests compare against `"OK"`.
- Add a `@testset` in `test/runtests.jl` for every new behavior.
- Prefer cross-platform paths (`normpath`, `joinpath`); development happens on Windows.

## Issues, Commits, and PRs

- Open an Issue to discuss motivation and compatibility before changing behavior; PRs after agreement.
- Commit messages: English, imperative mood, sentence case (e.g. "Add citation badge to README"); no prefix convention.
- Target branch is `main`. Run the full test suite before committing.

## Do Not

- Do not "fix" files under `templates/`: `{{{PKG}}}`, `{{{UUID}}}`, `{{{AUTHORS}}}` and filenames like `src/PKG.jl` are Mustache placeholders, not broken code.
- Do not edit `Manifest.toml` by hand; use Pkg commands (`Pkg.update()`, `Pkg.resolve()`, `Pkg.instantiate()`).
- Do not add dependencies to Project.toml manually; use `Pkg.add()` so the Manifest stays consistent.

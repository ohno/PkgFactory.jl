```@meta
CurrentModule = PkgFactory
```

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ohno.github.io/PkgFactory.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ohno.github.io/PkgFactory.jl/dev/)
[![Build Status](https://github.com/ohno/PkgFactory.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ohno/PkgFactory.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ohno/PkgFactory.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ohno/PkgFactory.jl)

# PkgFactory.jl

Documentation for [PkgFactory.jl](https://github.com/ohno/PkgFactory.jl).

## Installation

```julia
import Pkg; Pkg.add(url="https://github.com/ohno/PkgFactory.jl.git")
```

## Quick Start

```julia
import PkgFactory

PkgFactory.WebUI.start()
```

Open `http://127.0.0.1:8000/` in a browser. The web interface authenticates
with GitHub's OAuth device flow and uses the GitHub API to create the
repository, commit the selected template, create the `gh-pages` branch, and
configure the `DOCUMENTER_KEY` secret. The optional Codecov token is encrypted
into `CODECOV_TOKEN`. The OAuth access token is held only in the current
browser tab's memory and is not written to disk or browser storage. The flow
requests `repo`, `workflow`, `read:user`, and `read:org` permissions so the
generated commit may include GitHub Actions workflow files.

An interrupted setup can be continued by enabling **Resume an interrupted
setup**. PkgFactory checks that the existing `Project.toml` identifies the
expected package before continuing.

## Jupyter Notebook

The notebook API separates the read-only preview from the GitHub operation:

```julia
config = PkgFactory.PackageConfig(
    owner = "octocat",
    name = "MyPkg",
    authors = ["The Octocat"],
    description = "A package created from Jupyter",
)

plan = PkgFactory.preview(config)
display(plan)

github = PkgFactory.github_device_login()
PkgFactory.create!(plan; backend = github)
```

The device-flow token is kept only in the returned `GitHubAPI` object, whose
display is always redacted. Optional secrets such as the Codecov token are
passed only to `create!`, for example
`create!(plan; backend = github, codecov_token = ENV["CODECOV_TOKEN"])`.
The complete example is available in `examples/PkgFactory.ipynb`.

## Terminal interface

```julia
PkgFactory.LocalUI.CLI()
```

The interactive interface checks GitHub CLI authentication, lists only repository owners available to the authenticated account, discovers template sets from the `templates/` directory, and presents repository owners, templates, and visibility as numbered choices. `all-in-one` is the default template and `public` is the default visibility. It validates each answer, hides the Codecov token when the terminal supports secure input, and asks for confirmation before creating the repository. Prompts with a default display `(default: VALUE)`; prompts without a default may display `(example: VALUE)`. The final creation confirmation requires an explicit `y` or `n`. Package name availability is checked immediately after entry against both the selected owner's repositories and Julia's General registry. It asks whether to resume only when the selected repository already exists; otherwise, a conflicting name produces unused numeric-suffix suggestions and the selected replacement is rechecked. The generated Git commit uses the authenticated GitHub login and ID-based noreply email so GitHub can attribute it to the correct account.

The Codecov token is optional; leave it blank to skip creating the `CODECOV_TOKEN` repository secret. To configure coverage uploads before the new repository exists, use the **Global Upload Token** from the selected account or organization's settings in [Codecov](https://app.codecov.io/). Viewing or generating the token requires account owner or organization administrator access. See the [Codecov token guide](https://docs.codecov.com/docs/codecov-tokens).

The same workflow is also available as an API:

```julia
PkgFactory.LocalAPI.create_package(
    "OWNER_NAME",
    "MyPkg.jl",
    ["AUTHOR_NAME"],
    "My package description",
)
```

`create_package` uses the authenticated GitHub CLI session. It creates the repository and its initial commit, creates the `gh-pages` branch, and configures the `DOCUMENTER_KEY` repository secret. Pass a Codecov token as the optional fifth argument to also configure `CODECOV_TOKEN`.

If a previous attempt stopped after creating the repository, call `create_package_with_jll` with `resume = true`. When the repository already has a `main` branch, PkgFactory clones it and overwrites the paths supplied by the selected template while preserving the existing package UUID and files outside that template. A repository with `Project.toml` is updated only when its package name matches the requested package. If the rendered files already match, no update commit is created.

## API Reference

```@index
```

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

PkgFactory.LocalUI.CLI()
```

The interactive interface checks GitHub CLI authentication, lists only repository owners available to the authenticated account, discovers template sets from the `templates/` directory, and presents repository owners, templates, and visibility as numbered choices. `all-in-one` is the default template and `public` is the default visibility. It validates each answer, hides the Codecov token when the terminal supports secure input, and asks for confirmation before creating the repository. Examples and defaults are combined as `(example: VALUE, default: VALUE)`, while the final creation confirmation requires an explicit `y` or `n`. Package name availability is checked immediately after entry. It asks whether to resume only when the selected repository already exists; if resume is declined, it presents unused numeric-suffix suggestions and rechecks the selected replacement. The generated Git commit uses the authenticated GitHub login and ID-based noreply email so GitHub can attribute it to the correct account.

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

If a previous attempt stopped after creating the repository, call `create_package_with_jll` with `resume = true`. Existing repositories are never overwritten unless their `Project.toml` identifies the expected package.

## API Reference

```@index
```

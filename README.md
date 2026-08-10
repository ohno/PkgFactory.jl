# PkgFactory.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ohno.github.io/PkgFactory.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ohno.github.io/PkgFactory.jl/dev/)
[![Build Status](https://github.com/ohno/PkgFactory.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ohno/PkgFactory.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ohno/PkgFactory.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ohno/PkgFactory.jl)

This is a Julia package to create a GitHub repository and deploy Julia package templates. If you want to customize it, please use [PkgTemplates.jl](https://juliaci.github.io/PkgTemplates.jl/stable/).

## Quick Start

Start the interactive command-line interface and follow its prompts:

```julia
import PkgFactory

PkgFactory.LocalUI.CLI()
```

The interface checks GitHub CLI authentication, lists the personal account and organizations where the authenticated user can create repositories, discovers and lists the available template directories, collects the remaining settings, displays a confirmation, and then creates the package. Repository owners, templates, and visibility are selected by number; `all-in-one` and `public` are the respective defaults. Prompt examples and defaults are combined as `(example: VALUE, default: VALUE)`; the final creation confirmation requires an explicit `y` or `n`. Package name availability is checked immediately after entry. If the selected repository already exists, the interface asks whether to resume its setup; when resume is declined, it lists unused numeric-suffix suggestions and checks the selected replacement again. The initial commit is attributed to the authenticated GitHub account.

The Codecov token is optional; press Enter without entering one to skip creating the `CODECOV_TOKEN` repository secret. To configure coverage uploads before the new repository exists, use the **Global Upload Token** from the selected account or organization's settings in [Codecov](https://app.codecov.io/). Account owner or organization administrator access is required to view or generate it; see the [Codecov token guide](https://docs.codecov.com/docs/codecov-tokens). Set `ENV["CODECOV_TOKEN"]` before starting to avoid entering it interactively.

The same workflow is also available as an API:

```julia
PkgFactory.LocalAPI.create_package(
    "OWNER_NAME",
    "MyPkg.jl",
    ["AUTHOR_NAME"],
    "My package description",
)
```

The API creates the repository and its initial commit, creates the `gh-pages` branch, and configures `DOCUMENTER_KEY`. Pass the Codecov token as the optional fifth argument to also configure `CODECOV_TOKEN`.

## Documentation

See https://ohno.github.io/PkgFactory.jl.

## Citation

See [`CITATION.bib`](CITATION.bib) for the relevant reference(s).

## Developer Guide

See https://ohno.github.io/PkgFactory.jl/dev/.

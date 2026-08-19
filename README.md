# PkgFactory.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ohno.github.io/PkgFactory.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ohno.github.io/PkgFactory.jl/dev/)
[![Build Status](https://github.com/ohno/PkgFactory.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ohno/PkgFactory.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ohno/PkgFactory.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ohno/PkgFactory.jl)

This is a Julia package to create a GitHub repository and deploy Julia package templates. If you want to customize it, please use [PkgTemplates.jl](https://juliaci.github.io/PkgTemplates.jl/stable/).

## Quick Start

Run the following command in the Julia REPL or a notebook:

```julia
import Pkg; Pkg.add(url="https://github.com/ohno/PkgFactory.git")
```

After installation, load the package and start the browser interface:

```julia
import PkgFactory; PkgFactory.WebUI.start()
```

Open `http://127.0.0.1:8000/`, connect GitHub with the OAuth device flow, and
configure the package. The access token is kept only in the browser tab's
memory. The flow requests `repo`, `workflow`, `read:user`, and `read:org` so it
can generate package files and GitHub Actions workflows. The terminal workflow
remains available as `PkgFactory.LocalUI.CLI()`.

## Jupyter Notebook

Notebook workflows separate configuration, preview, authentication, and the
GitHub-changing operation into individual cells:

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

`preview` performs no network requests. The OAuth access token is kept inside
a redacted in-memory object and is not included in the plan. See the runnable
[Jupyter example](examples/PkgFactory.ipynb).

## Documentation

- Home: https://ohno.github.io/PkgFactory.jl
- User Guide: https://ohno.github.io/PkgFactory.jl/dev/user
- Developer Guide: https://ohno.github.io/PkgFactory.jl/dev/developer
- API Reference: https://ohno.github.io/PkgFactory.jl/dev/api

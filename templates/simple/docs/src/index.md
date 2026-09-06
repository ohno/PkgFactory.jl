```@meta
CurrentModule = {{{PKG}}}
```

# {{{PKG}}}.jl

[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg?logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB3aWR0aD0iMzUwIiBoZWlnaHQ9IjM1MCIgdmlld0JveD0iMCAwIDM1MCAzNTAiPgo8cGF0aCBmaWxsLXJ1bGU9Im5vbnplcm8iIGZpbGw9InJnYig3OS42JSwgMjMuNSUsIDIwJSkiIGZpbGwtb3BhY2l0eT0iMSIgZD0iTSAxNjMuMzk4NDM4IDI1MCBDIDE2My4zOTg0MzggMjkxLjQyMTg3NSAxMjkuODIwMzEyIDMyNSA4OC4zOTg0MzggMzI1IEMgNDYuOTc2NTYyIDMyNSAxMy4zOTg0MzggMjkxLjQyMTg3NSAxMy4zOTg0MzggMjUwIEMgMTMuMzk4NDM4IDIwOC41NzgxMjUgNDYuOTc2NTYyIDE3NSA4OC4zOTg0MzggMTc1IEMgMTI5LjgyMDMxMiAxNzUgMTYzLjM5ODQzOCAyMDguNTc4MTI1IDE2My4zOTg0MzggMjUwIFogTSAxNjMuMzk4NDM4IDI1MCAiLz4KPHBhdGggZmlsbC1ydWxlPSJub256ZXJvIiBmaWxsPSJyZ2IoMjIlLCA1OS42JSwgMTQuOSUpIiBmaWxsLW9wYWNpdHk9IjEiIGQ9Ik0gMjUwIDEwMCBDIDI1MCAxNDEuNDIxODc1IDIxNi40MjE4NzUgMTc1IDE3NSAxNzUgQyAxMzMuNTc4MTI1IDE3NSAxMDAgMTQxLjQyMTg3NSAxMDAgMTAwIEMgMTAwIDU4LjU3ODEyNSAxMzMuNTc4MTI1IDI1IDE3NSAyNSBDIDIxNi40MjE4NzUgMjUgMjUwIDU4LjU3ODEyNSAyNTAgMTAwIFogTSAyNTAgMTAwICIvPgo8cGF0aCBmaWxsLXJ1bGU9Im5vbnplcm8iIGZpbGw9InJnYig1OC40JSwgMzQuNSUsIDY5LjglKSIgZmlsbC1vcGFjaXR5PSIxIiBkPSJNIDMzNi42MDE1NjIgMjUwIEMgMzM2LjYwMTU2MiAyOTEuNDIxODc1IDMwMy4wMjM0MzggMzI1IDI2MS42MDE1NjIgMzI1IEMgMjIwLjE3OTY4OCAzMjUgMTg2LjYwMTU2MiAyOTEuNDIxODc1IDE4Ni42MDE1NjIgMjUwIEMgMTg2LjYwMTU2MiAyMDguNTc4MTI1IDIyMC4xNzk2ODggMTc1IDI2MS42MDE1NjIgMTc1IEMgMzAzLjAyMzQzOCAxNzUgMzM2LjYwMTU2MiAyMDguNTc4MTI1IDMzNi42MDE1NjIgMjUwIFogTSAzMzYuNjAxNTYyIDI1MCAiLz4KPGRlc2M%2BSnVsaWEgZG90cywgY29weXJpZ2h0IDIwMTItMjAyMiBTdGVmYW4gS2FycGluc2tpLiBDQyBCWS1OQy1TQSA0LjAuIGh0dHBzOi8vZ2l0aHViLmNvbS9KdWxpYUxhbmcvanVsaWEtbG9nby1ncmFwaGljczwvZGVzYz48L3N2Zz4%3D)](https://julialang.org/downloads/)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://{{{OWNER}}}.github.io/{{{PKG}}}.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://{{{OWNER}}}.github.io/{{{PKG}}}.jl/dev/)
[![CI](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![coverage](https://codecov.io/gh/{{{OWNER}}}/{{{PKG}}}.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/{{{OWNER}}}/{{{PKG}}}.jl)

{{{DESCR}}}

## Quick Start

Run the following command in the Julia REPL or a notebook:

```julia
import Pkg; Pkg.add(url="https://github.com/{{{OWNER}}}/{{{PKG}}}.jl.git")
```

After installation, run the following to load the package and verify it works:

```@repl
import {{{PKG}}}; {{{PKG}}}.hello()
```

## API Reference

For the generated API index and docstrings, see the [API Reference](api.md).

## Acknowledgments

This package is written in the [Julia programming language](https://julialang.org/), built on an initial project template generated using [PkgFactory.jl](https://github.com/ohno/PkgFactory.jl). This repository is hosted on [GitHub](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl), and continuous integration is run using [GitHub Actions](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions).

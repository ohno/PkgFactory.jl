# {{{PKG}}}.jl

[![Build Status](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/downloads/)

{{{DESCR}}}

## Quick Start

Run the following command in the Julia REPL or a notebook:

```julia
import Pkg; Pkg.add(url="https://github.com/{{{OWNER}}}/{{{PKG}}}.jl.git")
```

After installation, load the package and verify it works:

```julia
julia> import {{{PKG}}}; {{{PKG}}}.hello()
"Hello, World!"
```

## Acknowledgments

This package is written in the [Julia programming language](https://julialang.org/), built on an initial project template generated using [PkgFactory.jl](https://github.com/ohno/PkgFactory.jl). This repository is hosted on [GitHub](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl), and continuous integration is run using [GitHub Actions](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions).

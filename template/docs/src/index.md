```@meta
CurrentModule = {{{PKG}}}
```

# {{{PKG}}}.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://{{{OWNER}}}.github.io/{{{PKG}}}.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://{{{OWNER}}}.github.io/{{{PKG}}}.jl/dev/)
[![Citation](https://img.shields.io/badge/citation-BibTeX-778899)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/CITATION.bib)
[![License](https://img.shields.io/github/license/{{{OWNER}}}/{{{PKG}}}.jl)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/LICENSE)
[![Build Status](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/{{{OWNER}}}/{{{PKG}}}.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/{{{OWNER}}}/{{{PKG}}}.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![JET Test](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)
[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-contributor's%20guide-blueviolet)](https://github.com/SciML/ColPrac)

{{{DESCR}}}

## Installation

Run the following command in the Julia REPL or a notebook:

```julia
import Pkg; Pkg.add(url="https://github.com/{{{OWNER}}}/{{{PKG}}}.jl.git")
```

After installation, run the following to load the package and verify it works:

```@repl
import {{{PKG}}}; {{{PKG}}}.hello()
```

## User Guide

For detailed usage instructions and examples, see the [User Guide](user.md).

## Developer Guide

For contribution and maintenance workflows, see the [Developer Guide](developer.md).

## API Reference

```@index
```

## Citation

Use [CITATION.bib](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/CITATION.bib) to cite this package.

```@example
file = open("../../CITATION.bib", "r") # hide
text = Base.read(file, String) # hide
close(file) # hide
println(text) # hide
```

## Acknowledgments

This package is written in the [Julia programming language](https://julialang.org/), built on an initial project template generated using [PkgFactory.jl](https://github.com/ohno/PkgFactory.jl). This repository is hosted on [GitHub](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl), and continuous integration is run using [GitHub Actions](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions).

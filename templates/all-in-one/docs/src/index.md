```@meta
CurrentModule = {{{PKG}}}
```

# {{{PKG}}}.jl

[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg?logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB3aWR0aD0iMzUwIiBoZWlnaHQ9IjM1MCIgdmlld0JveD0iMCAwIDM1MCAzNTAiPgo8cGF0aCBmaWxsLXJ1bGU9Im5vbnplcm8iIGZpbGw9InJnYig3OS42JSwgMjMuNSUsIDIwJSkiIGZpbGwtb3BhY2l0eT0iMSIgZD0iTSAxNjMuMzk4NDM4IDI1MCBDIDE2My4zOTg0MzggMjkxLjQyMTg3NSAxMjkuODIwMzEyIDMyNSA4OC4zOTg0MzggMzI1IEMgNDYuOTc2NTYyIDMyNSAxMy4zOTg0MzggMjkxLjQyMTg3NSAxMy4zOTg0MzggMjUwIEMgMTMuMzk4NDM4IDIwOC41NzgxMjUgNDYuOTc2NTYyIDE3NSA4OC4zOTg0MzggMTc1IEMgMTI5LjgyMDMxMiAxNzUgMTYzLjM5ODQzOCAyMDguNTc4MTI1IDE2My4zOTg0MzggMjUwIFogTSAxNjMuMzk4NDM4IDI1MCAiLz4KPHBhdGggZmlsbC1ydWxlPSJub256ZXJvIiBmaWxsPSJyZ2IoMjIlLCA1OS42JSwgMTQuOSUpIiBmaWxsLW9wYWNpdHk9IjEiIGQ9Ik0gMjUwIDEwMCBDIDI1MCAxNDEuNDIxODc1IDIxNi40MjE4NzUgMTc1IDE3NSAxNzUgQyAxMzMuNTc4MTI1IDE3NSAxMDAgMTQxLjQyMTg3NSAxMDAgMTAwIEMgMTAwIDU4LjU3ODEyNSAxMzMuNTc4MTI1IDI1IDE3NSAyNSBDIDIxNi40MjE4NzUgMjUgMjUwIDU4LjU3ODEyNSAyNTAgMTAwIFogTSAyNTAgMTAwICIvPgo8cGF0aCBmaWxsLXJ1bGU9Im5vbnplcm8iIGZpbGw9InJnYig1OC40JSwgMzQuNSUsIDY5LjglKSIgZmlsbC1vcGFjaXR5PSIxIiBkPSJNIDMzNi42MDE1NjIgMjUwIEMgMzM2LjYwMTU2MiAyOTEuNDIxODc1IDMwMy4wMjM0MzggMzI1IDI2MS42MDE1NjIgMzI1IEMgMjIwLjE3OTY4OCAzMjUgMTg2LjYwMTU2MiAyOTEuNDIxODc1IDE4Ni42MDE1NjIgMjUwIEMgMTg2LjYwMTU2MiAyMDguNTc4MTI1IDIyMC4xNzk2ODggMTc1IDI2MS42MDE1NjIgMTc1IEMgMzAzLjAyMzQzOCAxNzUgMzM2LjYwMTU2MiAyMDguNTc4MTI1IDMzNi42MDE1NjIgMjUwIFogTSAzMzYuNjAxNTYyIDI1MCAiLz4KPGRlc2M%2BSnVsaWEgZG90cywgY29weXJpZ2h0IDIwMTItMjAyMiBTdGVmYW4gS2FycGluc2tpLiBDQyBCWS1OQy1TQSA0LjAuIGh0dHBzOi8vZ2l0aHViLmNvbS9KdWxpYUxhbmcvanVsaWEtbG9nby1ncmFwaGljczwvZGVzYz48L3N2Zz4%3D)](https://julialang.org/downloads/)
[![Colab: open](https://badgen.net/static/Colab/open/007ec6?icon=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNDAiIGhlaWdodD0iMTQwIiB2aWV3Qm94PSIwIDUgMjQgMTQiPjxwYXRoIHN0eWxlPSJmaWxsOiNlODcxMGE7IiBkPSJNMS45NzcsMTYuNzdjLTIuNjY3LTIuMjc3LTIuNjA1LTcuMDc5LDAtOS4zNTdDMi45MTksOC4wNTcsMy41MjIsOS4wNzUsNC40OSw5LjY5MWMtMS4xNTIsMS42LTEuMTQ2LDMuMjAxLTAuMDA0LDQuODAzQzMuNTIyLDE1LjExMSwyLjkxOCwxNi4xMjYsMS45NzcsMTYuNzd6Ii8%2BPHBhdGggc3R5bGU9ImZpbGw6I2Y5YWIwMDsiIGQ9Ik0xMi4yNTcsMTcuMTE0Yy0xLjc2Ny0xLjYzMy0yLjQ4NS0zLjY1OC0yLjExOC02LjAyYzAuNDUxLTIuOTEsMi4xMzktNC44OTMsNC45NDYtNS42NzhjMi41NjUtMC43MTgsNC45NjQtMC4yMTcsNi44NzgsMS44MTljLTAuODg0LDAuNzQzLTEuNzA3LDEuNTQ3LTIuNDM0LDIuNDQ2QzE4LjQ4OCw4LjgyNywxNy4zMTksOC40MzUsMTYsOC44NTZjLTIuNDA0LDAuNzY3LTMuMDQ2LDMuMjQxLTEuNDk0LDUuNjQ0Yy0wLjI0MSwwLjI3NS0wLjQ5MywwLjU0MS0wLjcyMSwwLjgyNkMxMy4yOTUsMTUuOTM5LDEyLjUxMSwxNi4zLDEyLjI1NywxNy4xMTR6Ii8%2BPHBhdGggc3R5bGU9ImZpbGw6I2U4NzEwYTsiIGQ9Ik0xOS41MjksOS42ODJjMC43MjctMC44OTksMS41NS0xLjcwMywyLjQzNC0yLjQ0NmMyLjcwMywyLjc4MywyLjcwMSw3LjAzMS0wLjAwNSw5Ljc2NGMtMi42NDgsMi42NzQtNi45MzYsMi43MjUtOS43MDEsMC4xMTVjMC4yNTQtMC44MTQsMS4wMzgtMS4xNzUsMS41MjgtMS43ODhjMC4yMjgtMC4yODUsMC40OC0wLjU1MiwwLjcyMS0wLjgyNmMxLjA1MywwLjkxNiwyLjI1NCwxLjI2OCwzLjYsMC44M0MyMC41MDIsMTQuNTUxLDIxLjE1MSwxMS45MjcsMTkuNTI5LDkuNjgyeiIvPjxwYXRoIHN0eWxlPSJmaWxsOiNmOWFiMDA7IiBkPSJNNC40OSw5LjY5MUMzLjUyMiw5LjA3NSwyLjkxOSw4LjA1NywxLjk3Nyw3LjQxM2MyLjIwOS0yLjM5OCw1LjcyMS0yLjk0Miw4LjQ3Ni0xLjM1NWMwLjU1NSwwLjMyLDAuNzE5LDAuNjA2LDAuMjg1LDEuMTI4Yy0wLjE1NywwLjE4OC0wLjI1OCwwLjQyMi0wLjM5MSwwLjYzMWMtMC4yOTksMC40Ny0wLjUwOSwxLjA2Ny0wLjkyOSwxLjM3MUM4LjkzMyw5LjUzOSw4LjUyMyw4Ljg0Nyw4LjAyMSw4Ljc0NkM2LjY3Myw4LjQ3NSw1LjUwOSw4Ljc4Nyw0LjQ5LDkuNjkxeiIvPjxwYXRoIHN0eWxlPSJmaWxsOiNmOWFiMDA7IiBkPSJNMS45NzcsMTYuNzdjMC45NDEtMC42NDQsMS41NDUtMS42NTksMi41MDktMi4yNzdjMS4zNzMsMS4xNTIsMi44NSwxLjQzMyw0LjQ1LDAuNDk5YzAuMzMyLTAuMTk0LDAuNTAzLTAuMDg4LDAuNjczLDAuMTljMC4zODYsMC42MzUsMC43NTMsMS4yODUsMS4xODEsMS44OWMwLjM0LDAuNDgsMC4yMjIsMC43MTUtMC4yNTMsMS4wMDZDNy44NCwxOS43Myw0LjIwNSwxOS4xODgsMS45NzcsMTYuNzd6Ii8%2BPC9zdmc%2B&iconWidth=22)](https://colab.research.google.com/github/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/examples/{{{PKG}}}.ipynb)
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://{{{OWNER}}}.github.io/{{{PKG}}}.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://{{{OWNER}}}.github.io/{{{PKG}}}.jl/dev/)
[![Citation](https://img.shields.io/badge/citation-BibTeX-778899)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/CITATION.bib)
[![license](https://img.shields.io/github/license/{{{OWNER}}}/{{{PKG}}}.jl?label=license)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/LICENSE)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)
[![contributer's guide: ColPrac](https://img.shields.io/badge/contributer%27s%20guide-ColPrac-blueviolet)](https://github.com/SciML/ColPrac)
[![CI](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![coverage](https://codecov.io/gh/{{{OWNER}}}/{{{PKG}}}.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/{{{OWNER}}}/{{{PKG}}}.jl)
[![Aqua](https://img.shields.io/github/actions/workflow/status/{{{OWNER}}}/{{{PKG}}}.jl/Aqua.yml?branch=main&event=push&label=Aqua&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA3OS4zNzUgNTguNjc0Ij48ZyBzdHJva2U9IiNmNWY1ZjUiIHN0cm9rZS13aWR0aD0iNC44ODciPjxjaXJjbGUgZmlsbD0iIzM4OTgyNiIgY3g9IjM5LjY4OCIgY3k9IjIzLjk5MiIgcj0iMjEuNTQ5Ii8%2BPGNpcmNsZSBmaWxsPSIjY2IzYzMzIiBjeD0iMTcuNDQzIiBjeT0iNDEuMjMxIiByPSIxNSIvPjxjaXJjbGUgZmlsbD0iIzk1NThiMiIgY3g9IjYxLjkzMiIgY3k9IjQxLjIzMSIgcj0iMTUiLz48L2c%2BPC9zdmc%2B)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/Aqua.yml?query=branch%3Amain)
[![JET](https://img.shields.io/github/actions/workflow/status/{{{OWNER}}}/{{{PKG}}}.jl/JET.yml?branch=main&event=push&label=%F0%9F%9B%A9%EF%B8%8F%20JET)](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions/workflows/JET.yml?query=branch%3Amain)

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

## User Guide

For detailed usage instructions and examples, see the [User Guide](user.md).

## Developer Guide

For contribution and maintenance workflows, see the [Developer Guide](developer.md).

## API Reference

For the generated API index and docstrings, see the [API Reference](api.md).

## Citation

Use [CITATION.bib](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/blob/main/CITATION.bib) to cite this package.

```@example
import {{{PKG}}} # hide
println(read(joinpath(pkgdir({{{PKG}}}), "CITATION.bib"), String)) # hide
```

## Acknowledgments

This package is written in the [Julia programming language](https://julialang.org/), built on an initial project template generated using [PkgFactory.jl](https://github.com/ohno/PkgFactory.jl). This repository is hosted on [GitHub](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl), and continuous integration is run using [GitHub Actions](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/actions).

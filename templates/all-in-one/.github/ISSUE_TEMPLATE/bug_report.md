---
name: Bug report
about: Create a report to help us improve
title: ''
labels: 'bug'
assignees: ''

---

## Summary

A clear and concise description of what the bug is.

## Minimal Reproducible Example

```julia
julia> sin(Inf)
ERROR: DomainError with Inf:
sin(x) is only defined for finite x.
Stacktrace:
 [1] sin_domain_error(x::Float64)
   @ Base.Math .\special\trig.jl:28
 [2] sin(x::Float64)
   @ Base.Math .\special\trig.jl:39
 [3] top-level scope
   @ REPL[2]:1
```

## Environment

```julia
julia> versioninfo()
Julia Version 1.10.10
Commit 95f30e51f4 (2025-06-27 09:51 UTC)
Build Info:
  Official https://julialang.org/ release
Platform Info:
  OS: Windows (x86_64-w64-mingw32)
  CPU: 8 × 11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-15.0.7 (ORCJIT, tigerlake)
Threads: 1 default, 0 interactive, 1 GC (on 8 virtual cores)

julia>  import Pkg; Pkg.status("{{{PKG}}}")
Status `C:\Users\user\.julia\environments\v1.10\Project.toml`
  [8fce2d05] {{{PKG}}} v0.0.1 `https://github.com/{{{OWNER}}}/{{{PKG}}}.jl.git#main`

```

## Additional context

Add any other context about the problem here.

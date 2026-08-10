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
# Paste the complete output here.

julia> import Pkg; Pkg.status("{{{PKG}}}")
# Paste the complete output here.

```

## Additional context

Add any other context about the problem here.

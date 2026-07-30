```@meta
CurrentModule = {{{PKG}}}
```

# User Guide

Before starting the tutorial, complete the [Installation](@ref) section. Feature requests and bug reports are handled through GitHub [Issues](https://github.com/{{{OWNER}}}/{{{PKG}}}.jl/issues).

## Tutorial

```@repl
import {{{PKG}}}
{{{PKG}}}.hello()
```

## Examples

```@example
import {{{PKG}}}
text_1 = {{{PKG}}}.hello()
text_2 = "Goodbye, World!"
text_1 * " " * text_2
```

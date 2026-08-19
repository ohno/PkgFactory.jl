```@meta
CurrentModule = {{{PKG}}}
```

# Examples

The examples below show how to load {{{PKG}}}.jl and use its generated starter function.

## Basic usage

```@repl
import {{{PKG}}}
{{{PKG}}}.hello()
```

## Composing the result

```@example
import {{{PKG}}}
greeting = {{{PKG}}}.hello()
"$(greeting) Welcome to {{{PKG}}}.jl."
```

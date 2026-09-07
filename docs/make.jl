using PkgFactory
using Documenter
using DocumenterMermaid

DocMeta.setdocmeta!(PkgFactory, :DocTestSetup, :(using PkgFactory); recursive=true)

makedocs(;
    modules=[PkgFactory],
    authors="Shuhei Ohno",
    sitename="PkgFactory.jl",
    format=Documenter.HTML(;
        canonical="https://ohno.github.io/PkgFactory.jl",
        edit_link="main",
        assets=["assets/logo.ico"],
    ),
    pages=[
        "Home" => "index.md",
        "Developer Guide" => "developer.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(;
    repo="github.com/ohno/PkgFactory.jl",
    devbranch="main",
)

# Developer Guide

This page describes how to develop PkgFactory.jl locally (tests, docs, and common maintenance tasks). For feature requests or behavior changes, please open an Issue first to discuss motivation, use-cases, and compatibility. Once we agree on the direction, PRs are welcome.

Generate Documentation:

```sh
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate();'
julia --project=docs --startup-file=no -e 'include("docs/make.jl")'
```

Run Tests:

```sh
julia --project=. --startup-file=no -e 'using Pkg; Pkg.test()'
```

Dependency Maintenance:

```sh
julia --project=. -e 'import Pkg; Pkg.update()'
julia --project=. -e 'import Pkg; Pkg.resolve()'
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

Development REPL (with Revise):

```sh
julia -i -E 'using Revise; import Pkg; Pkg.activate("."); using PkgFactory; PkgFactory.hello()'
```

Local API tests replace the command runner and SSH key generator with test doubles. The default test suite must not create repositories, change GitHub authentication, or write repository secrets. End-to-end checks should use a dedicated account and repository and must not run in the default CI workflow.

OAuth Device Flow Sequence Diagram:

```mermaid
sequenceDiagram
  autonumber
  participant UI as UI (CLI or Web)
  participant App as PkgFactory.jl
  participant GitHub as GitHub Rest API & Web

  %% get device code
  UI->>App: call API (Oxygen.jl)
  App->>GitHub: POST /login/device/code (device_flow_begin)
  GitHub-->>App: device_code
  App-->>UI: device_code

  %% get access token
  UI->>GitHub: visit website (copy & paste device_code)
  GitHub-->>UI: redirect (or go back by hand)
  UI->>App: call API (Oxygen.jl)
  App->>GitHub: POST /login/oauth/access_token (device_flow_end)
  GitHub-->>App: access_token
  App-->>UI: access_token

  %% create repo using access token
  UI->>App: call API (Oxygen.jl)
  App->>GitHub: create_repo, etc.
```

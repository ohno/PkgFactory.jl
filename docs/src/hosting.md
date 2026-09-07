# Hosting the Web UI

The Web UI uses each visitor's GitHub token, held in their browser tab and sent
in the Authorization header. The server does not persist access tokens. Closing
the tab clears its copy; it does not revoke the GitHub OAuth grant. No Auth0 or
credential database is required for this deployment model.

## One server behind HTTPS

Install Julia and OpenSSH (`ssh-keygen`, for documentation deploy keys).
Run one Julia process behind an HTTPS reverse proxy. Keep the Julia port private.
Set `PUBLIC_ORIGIN` to the exact browser origin (scheme and host, with a port if
nonstandard), and use a dedicated GitHub OAuth application's client ID with
device flow enabled:

```sh
export PUBLIC_ORIGIN=https://packages.example.com
export GITHUB_OAUTH_CLIENT_ID=YOUR_CLIENT_ID
```

```julia
using PkgFactory
PkgFactory.WebUI.start("127.0.0.1", 8000;
    trusted_proxies=["127.0.0.1", "::1"],
    requester=PkgFactory.WebAPI.GitHubTransport(connect_timeout=10, read_timeout=30))
```

For a Caddy proxy on the same host:

```caddyfile
packages.example.com {
    reverse_proxy 127.0.0.1:8000 {
        header_up X-Real-IP {remote_host}
    }
}
```

Only list immediate proxies you control in `trusted_proxies`. They must overwrite
`X-Real-IP`; client-supplied forwarding headers are otherwise ignored. With a
container network, use the actual proxy address and bind the application only
within that private network. Without trusted proxy configuration, requests share
the proxy's IP-based allowance.

The application limits request bodies to 64 KiB, including chunked uploads, and
limits active connections to 128. It accepts JSON objects for POST endpoints.
Origin headers must match `PUBLIC_ORIGIN`; API clients without Origin still need
GitHub authorization for repository operations. CSP and X-Frame-Options prevent
embedding the UI on other sites.

The following fixed-window limits apply per 60 seconds:

| Scope | Limit |
| --- | ---: |
| API requests per client IP (excluding health checks) | 120 |
| OAuth starts per client IP | 6 |
| OAuth polls per client IP | 60 |
| Creation attempts per token fingerprint | 5 |
| Active repository operations per Julia process | 8 |

Rate-limit responses use HTTP 429. The in-memory counters are bounded and reset
on restart. Deploy a single process: neither counters nor repository exclusion
coordinate across replicas. An external operation store/lock and distributed
rate limiting are required before scaling out. These controls bound individual
clients; use the hosting provider's network protections for distributed traffic.

GitHub calls have connect/read timeouts and do not automatically retry writes or
follow redirects. A browser timeout does not cancel an operation already accepted
by the server. Request logs contain only a generated request ID, a known route,
HTTP status and duration. Do not enable proxy logging of Authorization headers,
request bodies or OAuth response bodies. `/api/health` is a liveness endpoint,
not a test of GitHub availability.

## Recovery

WebAPI commits `.pkgfactory.json` atomically with the generated template. It
contains a settings fingerprint, Project.toml digest and operation state, with
no credentials. `PkgFactory.preview` includes this additional file in its plan.
The final successful step records `complete` in a separate commit.

`POST /api/github/repository-status` takes `owner` and `package_name` plus the
caller's GitHub Bearer token. Its state is one of:

- `not_found`: GitHub returned 404 for this caller. Check the account and permissions.
- `unverified`: no recognized recovery marker. Inspect manually; automatic resume is refused.
- `files_committed`: the template commit is recorded; later setup may still be running or have failed.
- `complete`: the operation recorded completion. This is not a live audit of CI or later repository edits.

After a failed creation the UI checks this status without automatically retrying.
Resume requires the original owner, package, authors, description, template,
visibility and commit message, plus an unchanged Project.toml. Completed matching
operations return without further writes. Re-enter an optional Codecov token
when resuming because it is never retained in the marker or service.

Repositories made by older versions, or failures after repository creation but
before the template commit, have no marker. Inspect these manually; do not simply
select Resume. The server does not delete repositories, adopt arbitrary existing
repositories or roll back GitHub changes automatically.

Documenter recovery installs a new public/private key pair and updates the Secret
before deleting older keys titled `PkgFactory Documenter ...`. Other deploy keys
are preserved. If a Secret upload fails, the next explicit resume repairs the pair.

## Before opening registration

Exercise the real OAuth flow and package creation through the chosen HTTPS domain.
Check two accounts concurrently, revoked authorization, GitHub throttling, lost
responses and a restart during creation. Measure peak memory before selecting the
VPS size. Unit tests use a simulated GitHub service; local HTTP tests exercise
request limits and caller isolation without creating real repositories.

Build these docs locally without deployment using `julia --project=docs docs/build.jl`.
`docs/make.jl` is the CI entry point that also calls `deploydocs`.

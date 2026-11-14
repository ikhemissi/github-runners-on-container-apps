# Decisions

Where the build departs from [PRD-001](prd/PRD-001-ephemeral-runners.md) or fills a gap, and why. Newest last.

| # | Date | Decision | Why |
|---|---|---|---|
| D1 | 2026-11-14 | **Terraform deployed by azd, one root** (`infra/`) built from shared modules (state backend created by a preprovision step, Log Analytics, registry, Key Vault, Container Apps environment), instead of `infra/bootstrap` + `modules/` + `envs/dev`. The runner job is the project's own file and module. | Same Entra-authenticated state, preview before apply and a clean teardown, with less code to maintain; tags a tenant requires come from the azd environment (`RESOURCE_TAGS`), never from files. |
| D2 | 2026-11-14 | The JWT's issuer is the Registrar App's **client ID** (`GH_REGISTRAR_CLIENT_ID`). | GitHub's documentation recommends the client ID over the app ID. |
| D3 | 2026-11-14 | GitHub REST calls send `X-GitHub-Api-Version: 2026-03-10`. | The latest supported version (`GET /versions`); the JIT endpoint and its body are unchanged in it. |
| D4 | 2026-11-14 | The image adds only the Azure CLI, the GitHub CLI, Node LTS and `libatomic1` (Node needs it). Node comes as `.tar.gz`. | `curl`, `jq`, `openssl`, `git` and Python 3 are already in the official image; it has no `xz`. |
| D5 | 2026-11-14 | Retries use curl's own (`--retry 2`: 3 attempts on 408, 429 and 5xx, with backoff and `Retry-After`). | The brief's behaviour without a retry loop of our own. |
| D6 | 2026-11-14 | Secrets stay in shell variables; the private key reaches `openssl` through a file descriptor, headers through stdin. | Nothing on disk and nothing on a command line, except the JIT configuration that `run.sh --jitconfig` requires (see [SECURITY](SECURITY.md)). |
| D7 | 2026-11-14 | The repository is public; its own CI and image builds run on GitHub-hosted runners. | Public repositories don't use the minutes these runners are meant to save. |
| D8 | 2026-11-14 | The workflows that run **on** these runners (`smoke-test.yml`, later `print-oidc-claims.yml`) live in `examples/target-repository/`, to copy into the private repository they serve. | Self-hosted runners must never take jobs of a public repository, whose pull requests come from anyone. |
| D9 | 2026-11-14 | Workflows request `runs-on: aca-agent` alone, not `[self-hosted, aca-agent]`. | A runner registered with `generate-jitconfig` reported only the labels it was given (`aca-agent`), none of the default `self-hosted`, `Linux`, `X64`: a job asking for `self-hosted` would never match it. The scaler counts `aca-agent` with `noDefaultLabels`, so all three agree. |

## Open

- **Passwordless sudo:** the official image gives the `runner` user passwordless `sudo`, so job steps can become root in the container. Many actions rely on it (package installs). Kept for now; assessed with the managed identity test in Phase 3 ([SECURITY](SECURITY.md)).
- **Image size:** 2.5 GB (the official image is 1.6 GB, the Azure CLI most of the rest). Measure the start-up time of an execution in Phase 3 before slimming it.
- **Copilot cloud agent:** GitHub recommends ephemeral, single-use runners for it, which these are. Its firewall on self-hosted runners is still to check.
- **Self-hosted runner billing:** self-hosted minutes don't use the included minutes; a per-minute platform charge announced for private repositories was postponed (to recheck on GitHub's billing page before relying on it).

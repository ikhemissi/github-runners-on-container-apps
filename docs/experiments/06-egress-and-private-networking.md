# 06 — Egress control, private networking, and cancelled jobs

**Date:** 2026-11-15/16 · **Answers:** Q6, Q9 (partly), PRD-001 Phase 6 · **Versions:** image `gh-runner:e1410b7`, `egress-proxy:1894bc8` (Squid 6.14 on Ubuntu 24.04, `ubuntu/squid:6.6-24.04_edge` pinned by digest), azurerm 4.81, Terraform 1.15.8, tflint 0.66.0 (azurerm rules 0.33.0), Trivy 0.76.1

## Goal

1. **Q6:** a job that goes over its `timeout-minutes`, or many jobs at once, leave no execution running and no runner registered.
2. **Egress:** the runners reach the internet only through an allowlist proxy, and the target repository's CI still passes.
3. **Private networking:** a flag adds a private endpoint for Key Vault; off by default, so an existing environment's plan is unchanged.
4. **Terraform checks** that run in the public CI without Azure access.

## Setup

[infra/egress-proxy.tf](../../infra/egress-proxy.tf) and [infra/network.tf](../../infra/network.tf), behind `EGRESS_PROXY` and `PRIVATE_NETWORKING`:

- a virtual network with a subnet for the runners' environment and one for the proxy's;
- a network security group on the runners' subnet: the platform's service tags on port 443, then deny the internet;
- Squid ([egress-proxy/](../../egress-proxy/)) in its own internal Container Apps environment (one replica, 0.25 vCPU, 0.5 GiB, TCP ingress on 3128), allowing only the domains of [allowlist.txt](../../egress-proxy/allowlist.txt);
- the job's `HTTPS_PROXY`, `HTTP_PROXY` (both spellings), `NO_PROXY=localhost,127.0.0.1` and `NODE_USE_ENV_PROXY=1`.

## Steps and result

1. **10 smoke tests at once** (at most 3 executions): all 10 succeeded; 10 executions, none left running, no runner left registered.
2. **A job over its timeout** (`timeout-minutes: 1`, a step sleeping 150 s): GitHub cancelled it after 75 s; the execution ended 5 s later; no runner left.
3. **The flags off:** `azd provision --preview` showed only a new output; no resource changed.
4. **The egress proxy on:** 13 resources added; the runners' environment and the job replaced (changing an environment's subnet replaces it; deleting the old one took 22 min, creating each new one about 4 min).
5. **Two subnet rules the plan didn't show:**
   - creating the job failed (`Unable to get value using Managed identity … timeout after 5s`) until the subnet allowed `AzureKeyVault.<region>`: the job's Key Vault reference (the Scaler App's key) is read from that subnet;
   - no execution started: the scale rule logged `could not get access_tokens from GitHub API … context canceled` (`KEDAScalerFailed`). The scaler runs in the runners' environment and doesn't use the proxy. The subnet now allows GitHub's API addresses, read from `https://api.github.com/meta` at each plan.

   The target repository's CI could not get a runner for about 2.5 hours while this was found.
6. **The smoke test through the proxy** passed: registration, the Key Vault read, the OIDC sign-in. Its egress step: an allowlisted domain answered (200), another domain was refused by the proxy (403), and `pypi.org` without the proxy got no connection.
7. **The target repository's CI** (book, tests, five adapters, workflow lint) passed after two domains were added from the proxy's log of denied requests: `releases.astral.sh` (uv's downloads) and `api.mystmd.org` (the book's theme). Also denied, and left denied: Azure CLI telemetry (`dc.services.visualstudio.com`) and `checkip.amazonaws.com`.
8. **Requests seen** in one smoke test: about 20 hosts, all GitHub (`*.actions.githubusercontent.com`, `api.github.com`, `codeload.github.com`, results storage on `*.blob.core.windows.net`), Key Vault, `login.microsoftonline.com` and `management.azure.com`.
9. **Start-up with the proxy:** a queued job started about 60–70 s after it was queued (scaler polling 30 s, then about 30 s of start-up), as before.
10. **The proxy as a non-root user** (`USER 13`, Squid's `proxy`, no pid file): the image's tests pass; deployed with an in-place update.
11. **Private networking** (`PRIVATE_NETWORKING`): code and offline tests only (a private endpoints subnet, the `privatelink.vaultcore.azure.net` zone, Key Vault's private endpoint); not deployed.
12. **Offline Terraform checks** (`make test-infra`, CI job `infra`): format, validation, tflint, Trivy (three accepted findings in [.trivyignore.yaml](../../.trivyignore.yaml)), and `terraform test` with mock providers for the root (4 runs) and every module.

## Conclusion

- **Q6, answered:** cancelled and timed-out jobs end their execution within seconds, and no test left a runner registered.
- **Egress:** workflow steps reach only the allowlisted domains; the runners' subnet can't reach the internet directly but for GitHub's API addresses, which the scaler needs. Keeping the allowlist current is a maintenance task: the proxy's log lists every denied request ([OPERATIONS](../OPERATIONS.md)).
- **Not shown:** the proxy's monthly cost (one replica always on), to read in Cost analysis after a month; private networking deployed.
- **Next:** the Copilot cloud agent can now be tried on these runners (D18, Q9).

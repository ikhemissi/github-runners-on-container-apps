# Security

How each requirement of [PRD-001](prd/PRD-001-ephemeral-runners.md) is met, and what remains. Completed phase by phase.

## Secrets

| Secret | Where it lives | Who can read it |
|---|---|---|
| Scaler App private key | Key Vault secret, uploaded by hand | the job's `runtime` identity, as a Key Vault-referenced secret of the scale rule (never an environment variable) |
| Registrar App private key | Key Vault secret, uploaded by hand | the entrypoint, at start-up, with the `runtime` identity |
| Installation token (1 hour) | a shell variable of the entrypoint | nobody else: cleared before the runner starts |
| JIT configuration | an argument of `run.sh` | the runner; visible to job steps in the process list while the job runs (single-use, bound to this runner) |

No personal access token, client secret, registry admin user or storage key exists. Terraform never reads a secret value.

## What the entrypoint does (Phase 1, tested offline)

- Reads the registrar key through the managed identity endpoint (`client_id` of the `runtime` identity), keeps it in memory and passes it to `openssl` through a file descriptor.
- Asks for an installation token limited to the one repository and to Administration: write.
- Before starting the runner, clears `IDENTITY_ENDPOINT`, `IDENTITY_HEADER`, `MSI_ENDPOINT`, `MSI_SECRET` and every registrar setting; the tests check the runner's environment.
- Never logs a token, a key or the JIT configuration; the tests check the logs.

## Residual risks

- **The managed identity endpoint may still be reachable from job steps**, although its variables are cleared: steps run in the container that had the `runtime` identity. To test in Phase 3, from a workflow step. Mitigations: the Registrar App is installed on one repository with one permission, runners are single-use and labelled, and the job has nothing else. A future option, not built: a small token broker that mints JIT configurations, so the job never holds an App key.
- **Passwordless sudo** in the official image: job steps can become root in the container ([DECISIONS](DECISIONS.md), open).

## Workflows

- Private repository only; workflows from forks must not run on these runners (repository setting, and `if:` guards).
- `permissions:` least privilege in every workflow (`contents: read`; `id-token: write` only where OIDC is used); third-party actions pinned by commit SHA.

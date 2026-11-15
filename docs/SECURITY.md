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

- **The managed identity endpoint is reachable from job steps** (`http://localhost:12356/msi/token`), but answers **403** without its header, and no process's environment keeps the header, as checked as root from a step (experiment 03). The smoke test checks this on every run. Mitigations: the Registrar App is installed on one repository with one permission, runners are single-use and labelled, and the job has nothing else. A future option, not built: a small token broker that mints JIT configurations, so the job never holds an App key.
- **Passwordless sudo** in the official image: job steps can become root in the container ([DECISIONS](DECISIONS.md), open).

## Workflows

- Private repository only; workflows from forks must not run on these runners (repository setting, and `if:` guards).
- `permissions:` least privilege in every workflow (`contents: read`; `id-token: write` only where OIDC is used); third-party actions pinned by commit SHA.

## Azure sign-in from workflows (Phase 5)

- Workflow steps sign in as the `deployer` identity through GitHub OIDC: a federated credential trusts the tokens of the target repository's `azure-dev` environment only, and that environment accepts the `main` branch only. No client secret exists.
- The `deployer` identity is never attached to the job, and its role is Reader on one resource group by default (`RUNNER_DEPLOYER_SCOPE`, `RUNNER_DEPLOYER_ROLE`).
- A monthly budget alerts the resource group's Owners at 80 % of the actual spend and 100 % of the forecast.

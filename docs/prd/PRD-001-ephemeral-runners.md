# PRD-001 — Ephemeral GitHub Actions runners on Azure Container Apps jobs

**Status:** accepted · **Date:** 2026-11-14

## Problem

A private repository's workflows, including long-running coding-agent workflows (up to about 3 hours), use GitHub-hosted minutes that run out mid-month. They should run on Azure compute that costs nothing while no job is queued.

## Target behaviour

A workflow job is queued → the KEDA `github-runner` scaler sees it → Container Apps starts **one job execution** → the container registers **one just-in-time (JIT), single-use runner** → the runner runs **exactly one job** → the container exits. No queued job: zero executions.

Scope: one repository (a setting), repository-level runners only.

## Fixed decisions

| # | Decision |
|---|---|
| F1 | Terraform with `azurerm` (and `azapi` where needed), deployed by azd as one root built from shared modules ([DECISIONS](../DECISIONS.md) D1). GitHub resources are not managed by Terraform. |
| F2 | Compute: a Container Apps job, trigger type `Event`, KEDA `github-runner` scale rule. |
| F3 | Two GitHub Apps, no personal access tokens: a **Scaler App** (Actions: read, Metadata: read) used only by KEDA, and a **Registrar App** (Administration: read and write, Metadata: read) used only by the entrypoint. Each is installed on the target repository only. |
| F4 | Both private keys in Key Vault (RBAC), uploaded by hand (`az keyvault secret set --file`), never through Terraform. The scaler key reaches KEDA as a Key Vault-referenced secret (never an environment variable); the registrar key is read at start-up with the job's identity. |
| F5 | User-assigned identities: `runtime` (attached to the job: AcrPull, Key Vault Secrets User on the two secrets only), `deployer` (never attached; workflow steps through GitHub OIDC; Reader on one resource group by default), optional `infra` (never attached; runs this Terraform from a workflow). |
| F6 | GitHub OIDC to Azure: federated credentials whose subject is a GitHub environment (e.g. `environment:azure-dev`), checked against a real token; created one after the other. |
| F7 | Registration with `POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig`, then `run.sh --jitconfig`. |
| F8 | Label `aca-agent`; the scaler counts it (`noDefaultLabels`, `targetWorkflowQueueLength=1`, `runnerScope=repo`; `enableEtags` off: [DECISIONS](../DECISIONS.md) D15); workflows use `runs-on: aca-agent` (a JIT runner has no default labels: [DECISIONS](../DECISIONS.md) D9). |
| F9 | Job settings (all settings, these defaults): 2 CPU, 4 Gi, 0–3 executions, polling 30 s, parallelism 1, completions 1, **no retry**, replica timeout 3 h 30. |
| F10 | v1 networking: Consumption environment without a virtual network; Key Vault public with RBAC only. Private networking behind `enable_private_networking` (Phase 6). |
| F11 | Image: the official runner image pinned by digest, plus the Azure CLI, the GitHub CLI and Node LTS; no Docker daemon (no container actions, no `services:`). |

## Phases (stop and report after each)

| Phase | Builds | Done when |
|---|---|---|
| 1 | Runner image and entrypoint, local test mode | lint clean, offline tests pass, a JIT runner registered from a laptop runs `smoke-test.yml` |
| 2 | Terraform foundation: state, Log Analytics, ACR, Key Vault, identities, RBAC | `azd provision --preview` clean, then provisioned |
| 3 | The job, started by hand | one execution registers one runner that runs one queued job |
| 4 | Event trigger and the KEDA rule | 0 queued → 0 executions; 1 → 1; 4 queued with max 3 → 3, then 1 |
| 5 | OIDC: federated credentials, `print-oidc-claims.yml`, `azure/login` in `smoke-test.yml` | `az account show` succeeds without any secret |
| 6 | Hardening behind flags: private networking, a budget alert, Log Analytics queries, an optional Terraform workflow | each flag planned and documented |

## Acceptance criteria

- A clean apply then plan shows no drift; destroy and re-apply work, apart from the documented key upload.
- No secret in the repository, the Terraform state, the image layers or the logs.
- Idle: zero executions.
- Every job gets a new runner name; runners disappear after their job; no offline runners left after 10 runs.
- A job over its `timeout-minutes` is stopped by GitHub, and the execution ends before the replica timeout.
- `smoke-test.yml` shows the runner name and labels, `az account show` through OIDC, and that `IDENTITY_ENDPOINT` is unset in the step.
- The documents let someone else rebuild everything in under an hour.

## Out of scope (v1)

Organization or enterprise runners, Docker-in-Docker or container jobs, GPU or Windows runners, several regions, a token broker, AKS/ARC and virtual machine scale sets.

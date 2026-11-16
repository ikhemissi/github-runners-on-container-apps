# Demo runbook

A step-by-step script to show the results, written so that someone else can run it. About 15 minutes.

## Before the demo

- [ ] The environment is up: `azd env get-value RUNNER_JOB_NAME` answers, and the smoke test passed today (step 2 below, run once beforehand).
- [ ] No runner is listed in the target repository (Settings → Actions → Runners): the list should be empty while idle.
- [ ] Tabs open: the target repository's Actions tab, its Settings → Actions → Runners, the resource group in the Azure portal, the Log Analytics workspace with the [OPERATIONS](OPERATIONS.md) queries, and the [overview](overview.svg).
- [ ] A shell with the azd environment selected (and its profile, [BOOTSTRAP](BOOTSTRAP.md#1-azure-environment-phase-2)).

## Steps

| # | Do | Show | Say |
|---|---|---|---|
| 1 | Open the README's overview and the runners page | An empty runner list; the job's executions in the portal | Nothing runs while idle: no VM, no runner waiting. |
| 2 | Run *Smoke test of the ephemeral runners* (`gh workflow run smoke-test.yml -R <owner>/<repo>`, the [example](../examples/target-repository/.github/workflows/smoke-test.yml)) | The run queued; within a minute a runner `job-runner-…` appears, takes the job, then disappears | One queued job, one execution, one just-in-time runner that takes exactly that job. |
| 3 | Open the smoke test's log | The identity step (HTTP 403), the egress step (200, 403, no connection), the Azure sign-in | The job can't use the runner's identity, reaches only allowlisted sites, and signs in to Azure through OIDC without a secret. |
| 4 | Open the job in the portal (Secrets, Identity) and Key Vault | A Key Vault reference for the Scaler App's key; the runtime identity with a role on two secrets only | The Apps' keys never leave Key Vault; there is no personal access token. |
| 5 | Run the denied-requests query ([OPERATIONS](OPERATIONS.md)) | The domains the proxy refused, with dates | Growing the allowlist is a log query and a one-line change. |
| 6 | Trigger the target repository's CI (a push or a re-run) | Several jobs, each on its own runner, in parallel | Up to four at once; each job gets a fresh machine. |
| 7 | Show a Copilot cloud agent session started with Environment → Actions | The *Copilot cloud agent* run on an `aca-agent` runner | The agent runs on the same runners, behind the same allowlist. |
| 8 | Open Cost Management for the resource group | The daily cost | The registry is the main cost while idle; executions cost only while they run. |

## If something fails

- **No runner appears after two minutes:** query `ContainerAppSystemLogs` for `KEDAScalerFailed` ([OPERATIONS](OPERATIONS.md), troubleshooting) and show the last successful smoke test run instead.
- **A step fails on a download:** show the denied-requests query; that is the allowlist doing its job.
- **No Azure access during the demo:** the smoke test runs and the experiments' write-ups ([experiments](experiments/README.md)) hold the recorded outputs.

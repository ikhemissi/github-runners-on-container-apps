# Findings — Ephemeral GitHub Actions runners on Azure Container Apps

**Date:** 14–16 November 2026 · **Versions tested:** actions-runner 2.338.2 (official image), Azure Container Apps jobs (Consumption profile, event trigger, KEDA `github-runner` scale rule), francecentral; Terraform 1.15.8, azurerm 4.81, azd; Azure CLI 2.92.0, GitHub CLI 2.104.0, Node 26.13.1, uv 0.13.8; Squid 6.14; Copilot cloud agent (November 2026)

## Summary

Ephemeral, single-use runners on Container Apps jobs work for a private repository's CI and for its Copilot cloud agent. Each queued job gets its own execution and just-in-time runner, which takes that one job and leaves; nothing runs while idle, and a job starts about a minute after it is queued. No personal access token or stored secret exists: two GitHub Apps' keys stay in Key Vault, read with a managed identity, and workflow steps reach Azure through GitHub OIDC as another identity. An allowlist proxy limits where the runners connect. What doesn't fit: anything that needs a container engine (container actions, `services:`, dev-container builds), which stays on GitHub-hosted runners.

## Answers

### Q1 — Can ephemeral, single-use GitHub Actions runners on Azure Container Apps jobs run a private repository's workflows (up to about 3 hours) securely, without PATs or stored secrets, at zero idle cost?

**Yes, for workflows that need no container engine, at near-zero idle cost.**

- **Ephemeral and single-use:** a JIT runner takes one job and is removed ([01](experiments/01-runner-image-locally.md), [03](experiments/03-job-started-by-hand.md)); the KEDA rule starts one execution per queued job (0 → 0, 1 → 1, 4 jobs with 3 at most → 3 then 1) once `enableEtags` is off, with a watchdog for the rest ([04](experiments/04-event-scaling.md), [D15](DECISIONS.md)); cancellations, timeouts and ten jobs at once left nothing behind ([06](experiments/06-egress-and-private-networking.md)).
- **A private repository's workflows:** the course repository's whole CI (tests, a Jupyter Book build, five evaluator adapters, workflow lint) and its Copilot cloud agent run on them ([06](experiments/06-egress-and-private-networking.md), [07](experiments/07-copilot-cloud-agent.md)). Workflows ask for `runs-on: aca-agent` ([D9](DECISIONS.md)) and add the setup action of tools the image lacks, such as Go. Container engines can't run in a Consumption execution ([03](experiments/03-job-started-by-hand.md), [D13](DECISIONS.md)).
- **Up to about 3 hours:** an execution may run 3.5 hours (`RUNNER_REPLICA_TIMEOUT`); the longest job run in the spike lasted a few minutes, so a 3-hour job remains to be run (below).
- **Securely, without PATs or stored secrets:** the Apps' keys are Key Vault secrets with a role per secret; the entrypoint clears the identity variables, and a step reaching the identity endpoint gets 403 ([03](experiments/03-job-started-by-hand.md)); steps sign in to Azure with OIDC, the subject read from a real token ([05](experiments/05-oidc-and-budget.md), [D16](DECISIONS.md)); egress can be limited to an allowlist ([06](experiments/06-egress-and-private-networking.md)). Residual risks: [SECURITY](SECURITY.md).
- **Idle cost:** no execution runs while idle. What remains is the registry (Basic, 0.1666 USD a day), the logs and, with egress control, the proxy's one replica. Measured: 0.58 USD on the deployment day, 1.50 USD on a day of heavy testing (Cost Management, November 2026).

The other questions (Q2–Q9) and their status: [QUESTIONS](QUESTIONS.md).

## What we would do differently

- **Run a long job** (about 3 hours) before relying on it: check that the execution and the runner hold for the whole job, and that the replica timeout stays above the longest `timeout-minutes`.
- **Measure a month's cost** with the proxy on, to replace the daily figures above.
- **Start with the network** if egress control is wanted: moving the environment into a virtual network replaced it and the job (about 25 minutes without runners), and the scaler and the job's Key Vault reference needed subnet rules the plan didn't show ([06](experiments/06-egress-and-private-networking.md)).
- **Open points:** passwordless `sudo` in the official image ([DECISIONS](DECISIONS.md), open); a token broker so that the job never holds an App key ([SECURITY](SECURITY.md)); private networking deployed (written, off, [D21](DECISIONS.md)); a second target repository would need its own App installation and a second job.

# 00 — Environment

**Date:** 2026-11-14 · **Versions:** see the table

## Goal

Record the environment every experiment runs in, so that results can be compared and retested.

## Setup

| Item | Value |
|---|---|
| Region | francecentral |
| Identities | user-assigned managed identities `runtime` (on the job), `deployer` and optional `infra` (GitHub OIDC only); two GitHub Apps (Scaler, Registrar) |
| Products and versions | Azure Container Apps jobs (Consumption), KEDA `github-runner` scaler, GitHub Actions runner 2.338.2, GitHub REST API 2026-03-10, Terraform + azd, Podman 4.9.3 locally |

## Result

Local tooling ready (experiment 01). The Azure environment comes in Phase 2: `azd env new runners-dev`, `RESOURCE_TAGS` if your tenant needs tags, `azd provision --preview`.

# 02 — The Terraform foundation

**Date:** 2026-11-14 · **Answers:** PRD-001 Phase 2 · **Versions:** Terraform 1.15.8, azurerm 4.81.0, azd, region francecentral

## Goal

Log Analytics, a container registry, Key Vault, the Container Apps environment, the `runtime` and `deployer` identities and their roles, with least privilege and no secret in the state. Done when the preview is clean, the apply succeeds and a second preview shows no change.

## Setup

An azd environment `runners-dev` with the tenant's tags in `RESOURCE_TAGS`; the shared Terraform state backend (Entra authentication) created by the preprovision step ([BOOTSTRAP](../BOOTSTRAP.md)). The project's own resources: [infra/runners.tf](../../infra/runners.tf).

## Steps

1. `azd provision --preview`, then `azd provision`.
2. `azd provision --preview` again (drift).
3. The identities' role assignments (`az role assignment list --assignee <principal> --all`).
4. The state, downloaded and searched for the secrets' placeholder.

## Result

1. Plan: 18 to add, 0 to change, 0 to destroy; the secrets' value shown as a write-only attribute. Applied in 5 min 25 s.
2. No changes.
3. `runtime`: AcrPull on the registry, and Key Vault Secrets User on the two secrets `github-app-scaler-key` and `github-app-registrar-key` only, not on the vault. `deployer`: Reader on the project's resource group. The resource group carries the tenant's tags and `azd-env-name`.
4. The placeholder appears 0 times in the state; `value_wo` is stored as `null`.

The first preview failed when azd's default sign-in belonged to another tenant: an azd profile using the Azure CLI's sign-in fixed it ([BOOTSTRAP](../BOOTSTRAP.md#1-azure-environment-phase-2)).

## Conclusion

The foundation matches PRD-001's identities and least privilege, without drift and without secret material in the state. Next: upload the Registrar App's key, then the job (Phase 3).

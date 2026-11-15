# 05 — Azure sign-in through OIDC, and a budget

**Date:** 2026-11-15 · **Answers:** Q7, Q9 (partly), PRD-001 Phase 5 and part of Phase 6 · **Versions:** `azure/login` v3.1.0, azurerm 4.81.0

## Goal

A workflow step on the runners signs in to Azure as the `deployer` identity through GitHub OIDC, without any secret; a monthly budget alerts on the resource group's spend.

## Setup

[infra/runner-oidc.tf](../../infra/runner-oidc.tf): one federated credential on the `deployer` identity, for the GitHub environment `azure-dev` of the target repository. [infra/budget.tf](../../infra/budget.tf): a monthly budget on the resource group. The target repository's environment `azure-dev` with three variables (the identity's client ID, the tenant, the subscription). The [smoke test](../../examples/target-repository/.github/workflows/smoke-test.yml) prints the token's claims, then runs `azure/login`.

## Steps and result

1. **Default subject** (`repo:<owner>/<repo>:environment:azure-dev`): `azure/login` failed with `AADSTS700213: No matching federated identity record`. The claims step showed the repository's actual subject, in the format with immutable IDs: `repo:<owner>@<owner id>/<repo>@<repo id>:environment:azure-dev`.
2. **That subject** in `RUNNER_DEPLOYER_OIDC_SUBJECT`, the credential updated in place: the sign-in succeeded and `az account show` listed the subscription, as a service principal, with no secret anywhere.
3. **The environment** then accepts the `main` branch only, so other branches can't sign in as the identity.
4. **Budget:** 50 a month in the billing currency, alerts at 80 % of the actual spend and 100 % of the forecast, to the resource group's Owners (no e-mail address configured). Its start date is kept in the state (`time_static`).
5. A plan also showed drift on the job (`workload_profile_name` set by the service): now declared in the job.

## Conclusion

Workflow steps reach Azure without secrets, as an identity the job never holds. The subject format must be read from a real token: newer repositories (or owners who opted in) use immutable IDs ([D16](../DECISIONS.md)). The Copilot cloud agent stays on GitHub-hosted runners until the runners have egress control ([D18](../DECISIONS.md)).

# Retest plan

What to run again when a product, an SDK or a policy changes, so that the findings stay true.

| Experiment | Retest when | How | Last run |
|---|---|---|---|
| [01](experiments/01-runner-image-locally.md) Runner image and entrypoint | a new runner image, Azure CLI, GitHub CLI, Node or uv version | `make lint test`, then `make push-runner`, set `RUNNER_IMAGE_TAG`, provision, run the smoke test | 2026-11-16 |
| [03](experiments/03-job-started-by-hand.md) Identity endpoint from steps | Container Apps identity changes; a new entrypoint | the smoke test's identity step (403 expected) | 2026-11-16 |
| [04](experiments/04-event-scaling.md) Scaling | the KEDA `github-runner` scaler or its metadata changes | queue 0, 1, then 4 jobs; count executions ([OPERATIONS](OPERATIONS.md), queries 1 and 5) | 2026-11-14 |
| [05](experiments/05-oidc-and-budget.md) OIDC sign-in | a new target repository or environment; GitHub's subject format | *OIDC token claims*, then the smoke test's sign-in | 2026-11-16 |
| [06](experiments/06-egress-and-private-networking.md) Egress and cancellations | the allowlist, the NSG rules, a new workflow tool; GitHub's published API addresses (a provision refreshes them) | the smoke test's egress step, the target repository's CI, the denied-requests query; a job cancelled at its timeout | 2026-11-16 |
| [07](experiments/07-copilot-cloud-agent.md) Copilot cloud agent | the agent's runner or firewall requirements; the repository's MCP servers | one session started with Environment → Actions; the denied-requests query | 2026-11-16 |
| Terraform | provider or module updates (`fast-start sync`) | `make test-infra`, then `azd provision --preview` (expect no change) | 2026-11-16 |

# Experiments

Numbered in the order they run; never renumbered. Copy [TEMPLATE.md](TEMPLATE.md) to `NN-<slug>.md`.

| # | Experiment | Questions | Result |
|---|---|---|---|
| 00 | [Environment](00-environment.md) | — | — |
| 01 | [The runner image and its entrypoint, locally](01-runner-image-locally.md) | Q2 | done: 23 offline checks; one real JIT runner ran one job and left |
| 02 | [The Terraform foundation](02-terraform-foundation.md) | PRD Phase 2 | done: 18 resources, no drift, roles on the two secrets only, no secret in the state |
| 03 | [The job, started by hand](03-job-started-by-hand.md) | Q2, Q5, Q8 | done: 36 s start to job, identity endpoint 403 from a step, Podman blocked |
| 04 | [Event-driven scaling](04-event-scaling.md) | Q3, Q4, Q6 | done: 0 → 0, 1 → 1, 4 → 3 + 1 once ETags are off; idle watchdog |
| 05 | [Azure sign-in through OIDC, and a budget](05-oidc-and-budget.md) | Q7, Q9 | done: sign-in without a secret (subject with immutable IDs); budget 50 a month |
| 06 | [Egress control, private networking, and cancelled jobs](06-egress-and-private-networking.md) | Q6, Q9 | done: allowlist proxy and NSG, course CI green behind it; no runner left after cancellations; private networking behind a flag |
| 07 | [The Copilot cloud agent on the runners](07-copilot-cloud-agent.md) | Q9 | done: sessions started with Actions run on `aca-agent` behind the proxy; Cloud sessions use GitHub's sandbox |
| 08 | [A three-hour job](08-long-job.md) | Q1, Q6 | done: 180 minutes on one runner, 36 heartbeats, execution ended 4 s after the job, nothing left |

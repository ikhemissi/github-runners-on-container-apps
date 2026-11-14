# Experiments

Numbered in the order they run; never renumbered. Copy [TEMPLATE.md](TEMPLATE.md) to `NN-<slug>.md`.

| # | Experiment | Questions | Result |
|---|---|---|---|
| 00 | [Environment](00-environment.md) | — | — |
| 01 | [The runner image and its entrypoint, locally](01-runner-image-locally.md) | Q2 | done: 23 offline checks; one real JIT runner ran one job and left |
| 02 | [The Terraform foundation](02-terraform-foundation.md) | PRD Phase 2 | done: 18 resources, no drift, roles on the two secrets only, no secret in the state |
| 03 | [The job, started by hand](03-job-started-by-hand.md) | Q2, Q5, Q8 | done: 36 s start to job, identity endpoint 403 from a step, Podman blocked |

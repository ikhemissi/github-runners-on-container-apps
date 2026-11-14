# Questions

| # | Question | Experiments | Status |
|---|---|---|---|
| Q1 | Can ephemeral, single-use GitHub Actions runners on Azure Container Apps jobs run a private repository's workflows (up to about 3 hours) securely, without PATs or stored secrets, at zero idle cost? | 01– | open |
| Q2 | Does a JIT runner registered with a GitHub App's installation token take exactly one job, then leave the repository's runner list? | 01, 03 | answered locally (01): one job, then gone; to confirm on Container Apps (03) |
| Q3 | Do the labels a JIT runner reports match what the KEDA scaler counts and what workflows request? | 01, 04 | partly answered: a JIT runner reports only its given labels, so workflows use `runs-on: aca-agent` (D9); the scaler's count is checked in 04 |
| Q4 | Does the scaler start exactly one execution per queued job, and none when idle (0 → 0, 1 → 1, 4 with max 3 → 3 then 1)? | 04 | open |
| Q5 | Can a job step still reach the managed identity endpoint once its variables are cleared, and what could it get? | 03 | open |
| Q6 | Does a job over its `timeout-minutes` stop, and its execution end before the replica timeout? Are runners ever left offline? | 03, 04 | open |
| Q7 | Which `sub` claim does the repository's OIDC token carry, and does `azure/login` work with it and no secret? | 05 | open |
| Q8 | How long does an execution take to start (image of 2.5 GB), and what does a month cost? | 03, 04 | open |
| Q9 | Can the Copilot cloud agent run on these runners (firewall, setup steps)? | later | open |

Status: `open`, `answered`, `partly answered`, `unanswered` (with what blocked it).

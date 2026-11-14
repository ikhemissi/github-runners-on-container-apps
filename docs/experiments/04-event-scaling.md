# 04 — Event-driven scaling

**Date:** 2026-11-14 · **Answers:** Q3, Q4, Q6 (partly), PRD-001 Phase 4 · **Versions:** image `gh-runner:70a08ef`, Container Apps jobs with the KEDA `github-runner` scale rule (Scaler App key as a Key Vault reference), francecentral

## Goal

The scale rule starts one execution per queued job with the runners' label, none when idle, and no more than the maximum: 0 queued → 0, 1 → 1, 4 with a maximum of 3 → 3, then 1.

## Setup

The job of [infra/runner-job.tf](../../infra/runner-job.tf) with the event trigger: `runnerScope=repo`, `labels=aca-agent`, `noDefaultLabels=true`, `targetWorkflowQueueLength=1`, 0 to 3 executions, polling every 30 s. Switching from the manual trigger replaced the job (a planned replacement). The smoke test dispatched in the private target repository.

## Steps and result

1. **Nothing queued, 150 s:** 0 executions.
2. **With `enableEtags=true` (the brief's setting):**
   - 1 queued → **2 executions** in the same second: KEDA logged `MetricValue: 2.00` for one job. One ran the job; the other's runner waited for a job that never came.
   - The metric then **stayed at 1.00 for 20 minutes with nothing queued**; with 4 queued it read 5.00. Every idle execution that ended was replaced by another one about six minutes later.
   - KEDA's source (`GetWorkflowQueueLength`) counts jobs that are queued *or in progress*, from two requests (queued runs, in-progress runs), without removing a run present in both; with ETags, unchanged answers come from its cache.
3. **Idle watchdog** (entrypoint): a runner with no job within `RUNNER_IDLE_TIMEOUT` (300 s) removes its own registration, and its execution ends; spare executions ended after about six minutes, no runner was left.
4. **With `enableEtags=false`:** the metric fell to 0.00 as soon as the scaler restarted, and no execution started while idle. 1 queued → **1** execution; 4 queued → **3**, then **1** when the first finished; every run succeeded; no runner left.

## Conclusion

Scaling works as PRD-001 asks with `enableEtags=false` ([D15](../DECISIONS.md)); the watchdog stays, for cancelled runs and for any double count left in the scaler. An execution costs about 45 s for the smoke test, and nothing runs while idle. Still open: 10 consecutive runs without an orphaned runner, and a job over its `timeout-minutes` (Q6).

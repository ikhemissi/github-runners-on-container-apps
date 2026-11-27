# 09 — A queued run the scaler missed, and the queue watchdog

**Date:** 2026-11-27 · **Answers:** Q3 · **Versions:** Container Apps jobs (KEDA `github-runner` scaler, as in KEDA 2.18), GitHub REST API 2026-03-10, Azure Functions Flex Consumption, .NET 10 isolated worker

## Goal

Explain why a pull request's three jobs waited 80 minutes for a runner, and add a safeguard that starts runners when the scale rule doesn't.

## Setup

Five runner jobs (one per repository, D24), egress proxy on. The workflow asked for `runs-on: aca-agent`.

## Steps

1. Compare what GitHub reports for the waiting run with what the scaler reads.
2. Unblock the run by hand (`az containerapp job start`, three times).
3. Build and deploy the queue watchdog ([D26](../DECISIONS.md)); check its first runs.
4. Simulate a scaler that sees nothing (the main runner job's polling interval set to 3600 s), queue the smoke test, and check that the watchdog starts its runner; restore the job with `azd provision`.

## Result

- The run (`pull_request`) and its three jobs were `queued` from 17:18 UTC; the unfiltered `GET /repos/<owner>/<repo>/actions/runs` listed it as `queued`, but `?status=queued` and `?status=in_progress` returned `total_count: 0` at 18:35. The scaler lists runs with exactly these two filtered requests ([its source](https://github.com/kedacore/keda/blob/v2.18.0/pkg/scalers/github_runner_scaler.go#L636)), so it counted 0: no execution, no `KEDAScalerFailed`, nothing in the logs between 16:55 and 18:36.
- Network, proxy, Key Vault sync and the scaler's settings were as expected; GitHub's status page listed no incident.
- Three executions started by hand took the three jobs (all passed). Within 50 s of the first job starting, the scaler counted 3 (`KEDAJobMetricActive 3.00` at 18:37:48): once the run changed state, the filtered list returned it. The three executions the scaler then started got no job and were removed by the idle watchdog within 4 minutes.
- The queue watchdog's first runs (21:10 UTC) read the key, got an Actions: read token for the five repositories, listed their runs and the jobs' executions: `0 job(s) queued for 00:05:00 or more … starting 0`, no error.
- Deploying it, one role assignment failed once with `could not find role` right after the custom role's creation; a second `azd provision` created it (propagation delay).

- With the main runner job's polling at 3600 s, the smoke test was queued at 21:13:19; the 21:20:09 run logged `the scaler left 1 job(s) without a runner; starting 1 execution(s)`, the execution started at 21:20:09 and the job ran from 21:20:44 to 21:21:06 (success): 7.5 minutes from queued to running. `azd provision` then restored the polling (preview: that one change).

## Conclusion

The scale rule depends on GitHub's status-filtered run list; when that list leaves a run out, nothing starts and nothing reports an error. The watchdog reads the unfiltered list and bounds the wait to about 5 to 10 minutes. Why GitHub's filter left the run out is not known.

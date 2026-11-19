# 08 — A three-hour job

**Date:** 2026-11-19 · **Answers:** Q1, Q6 · **Versions:** image `gh-runner:e1410b7` (2 vCPU, 4 GiB), egress proxy on, replica timeout 12,600 s

## Goal

The last open check of [the findings](../FINDINGS.md): one job of about three hours runs to its end on one ephemeral runner, whose execution and registration hold for the whole job and leave nothing behind.

## Setup

The target repository's workflow `runner-long-job.yml` (manual, `runs-on: aca-agent`, `timeout-minutes: 200`): one step waits 180 minutes and logs a heartbeat every 5 minutes (time, uptime, available memory); then the job calls the GitHub API with its own token and reaches `api.github.com` through the proxy. Nothing else ran on the runners during the job, apart from the repository's CI in its first four minutes.

## Steps

1. Started the workflow at 17:26:47 UTC (`gh workflow run runner-long-job.yml -f minutes=180`).
2. Watched the run and the job's executions every 8 minutes (`gh run view`, `az containerapp job execution list`).
3. Read the job's log, the execution's start and end, and the repository's registered runners after the end.

## Result

| | Value |
|---|---|
| Execution | started 17:26:50, ended 20:27:32 UTC (3 h 0 min 42 s), status Succeeded |
| Job | started 17:27:23, completed 20:27:28 UTC, conclusion success |
| Heartbeats | 36, every 5 minutes, none missing (17:27:24 to 20:22:25) |
| Available memory | 3,882 to 4,245 MiB through the job |
| At the end | GitHub API with the job's token: answered; `api.github.com` through the proxy: HTTP 200 |
| Afterwards | no execution running, no runner registered in the repository |

## Conclusion

- **Q1:** a three-hour job ran to its end on one ephemeral runner, with the replica timeout (3.5 hours) above the job's `timeout-minutes` (200), and the job token and the egress path still worked at the end.
- **Q6:** the execution ended 4 seconds after the job, and nothing was left registered.
- Not shown: a job that is busy for three hours (this one mostly waited), nor one longer than the replica timeout, which the execution would end.

# Operations

How to see what the runners do, and what to do when something looks wrong. The queries run in the Log Analytics workspace of the resource group (portal: the workspace → Logs), or from a shell:

```bash
export AZD_CONFIG_DIR=~/.azd-<tenant>   # if azd uses its own profile (BOOTSTRAP.md)
ws=$(az monitor log-analytics workspace list -g "$(azd env get-value AZURE_RESOURCE_GROUP)" --query "[0].customerId" -o tsv)
az monitor log-analytics query -w "$ws" --analytics-query "$(cat query.kql)" -o json
```

Replace the job's name in `let job = …` with `azd env get-value RUNNER_JOB_NAME`. Logs reach the workspace a few minutes late.

## Queries

**Executions per day**, and how many failed:

```kusto
// Executions per day, and how many ended with a non-zero exit code.
let job = "job-runner-runners-dev";
ContainerAppSystemLogs
| where JobName == job and Reason == "ContainerTerminated"
| extend exitCode = toint(extract(@"exit code '(\d+)'", 1, Log))
| summarize executions = count(), failed = countif(exitCode != 0) by day = bin(TimeGenerated, 1d)
| order by day desc
```

**Durations** (one short job: about 1 minute; an execution removed for lack of a job: about 6):

```kusto
// How long executions last, per day (minutes, from creation to completion).
let job = "job-runner-runners-dev";
let created = ContainerAppSystemLogs
    | where JobName == job and Reason == "SuccessfulCreate"
    | extend execution = extract(@"Job Execution '([^']+)'", 1, Log)
    | project execution, created = TimeGenerated;
let ended = ContainerAppSystemLogs
    | where JobName == job and Reason == "Completed"
    | extend execution = extract(@"Execution '([^']+)'", 1, Log)
    | project execution, ended = TimeGenerated;
created
| join kind=inner ended on execution
| extend minutes = (ended - created) / 1m
| summarize executions = count(), p50 = round(percentile(minutes, 50), 1), p95 = round(percentile(minutes, 95), 1),
    longest = round(max(minutes), 1) by day = bin(created, 1d)
| order by day desc
```

**Entrypoint problems**: failures, errors, and runners removed by the idle watchdog:

```kusto
// What the entrypoint reported besides the normal phases: failures (exit), errors, and runners removed for lack of a job (idle).
let job = "job-runner-runners-dev";
ContainerAppConsoleLogs
| where JobName == job and Log startswith "{"
| extend entry = parse_json(Log)
| where tostring(entry.phase) in ("exit", "error", "idle")
| project TimeGenerated, phase = tostring(entry.phase), runner = tostring(entry.runner), message = tostring(entry.message)
| order by TimeGenerated desc
```

**Start-up time** (about 30 s for the 2.5 GB image, November 2026):

```kusto
// Seconds from an execution's creation to its runner starting (image pull, Key Vault, GitHub calls).
let job = "job-runner-runners-dev";
let created = ContainerAppSystemLogs
    | where JobName == job and Reason == "SuccessfulCreate"
    | extend execution = extract(@"Job Execution '([^']+)'", 1, Log)
    | project execution, created = TimeGenerated;
ContainerAppConsoleLogs
| where JobName == job and Log startswith "{"
| extend entry = parse_json(Log)
| where tostring(entry.phase) == "run"
| project execution = tostring(entry.execution), started = TimeGenerated
| join kind=inner created on execution
| extend seconds = (started - created) / 1s
| summarize executions = count(), p50 = round(percentile(seconds, 50)), p95 = round(percentile(seconds, 95)) by day = bin(created, 1d)
| order by day desc
```

**What the scaler counted** (see [D15](DECISIONS.md)):

```kusto
// The queued jobs the scaler counted, every 5 minutes: above zero with nothing queued means it over-counts (D15).
let job = "job-runner-runners-dev";
ContainerAppSystemLogs
| where JobName == job and Reason in ("KEDAJobMetricActive", "KEDAJobMetricInactive")
| extend counted = todouble(extract(@"MetricValue: ([\d.]+)", 1, Log))
| summarize counted = max(counted) by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

## When something looks wrong

| Symptom | Check | Fix |
|---|---|---|
| A job waits for a runner | The workflow asks for `runs-on: aca-agent` (not `[self-hosted, aca-agent]`); query 5 counts it; `az containerapp job execution list` shows executions | A failed execution: query 3 gives the phase and reason (exit 1 settings, 2 Azure, 3 GitHub) |
| Executions start with nothing queued | Query 5 above zero while idle | `enableEtags` must stay `false`; the watchdog ends each idle execution after `RUNNER_IDLE_TIMEOUT` |
| A runner stays listed, offline | Settings → Actions → Runners of the target repository | Remove it there (`gh api -X DELETE repos/<owner>/<repo>/actions/runners/<id>`); look for its execution in query 3 |
| Key Vault read fails at start (exit 2) | The key secret's latest version is the PEM, not the placeholder; the runtime identity's role on that secret | Upload the key again ([BOOTSTRAP](BOOTSTRAP.md#3-upload-the-keys-to-key-vault)) |
| The budget alert arrives | Cost analysis of the resource group; query 1 and 2 for unusual volume or durations | Lower `RUNNER_MAX_EXECUTIONS`, find long or idle executions |

Stop a running execution: `az containerapp job stop -n <job> -g <resource group> --job-execution-name <execution>`. Rotate a GitHub App key: [BOOTSTRAP](BOOTSTRAP.md#3-upload-the-keys-to-key-vault).

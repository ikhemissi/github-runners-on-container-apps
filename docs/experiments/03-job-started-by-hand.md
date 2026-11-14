# 03 — The job, started by hand

**Date:** 2026-11-14 · **Answers:** Q2, Q5, Q8 (partly), PRD-001 Phase 3 · **Versions:** image `gh-runner:4d68757` (runner 2.338.2, uv 0.13.8), Container Apps jobs (Consumption), francecentral

## Goal

One execution registers one runner that takes one queued job, then exits; the registrar key comes from Key Vault through the job's managed identity; a job step can't use that identity. Also: how long an execution takes to start, and whether a container engine (Podman) can run in the job, for the target repository's dev-container job.

## Setup

The job from [infra/runner-job.tf](../../infra/runner-job.tf), manual trigger, 2 vCPU and 4 GiB, no retry, 12,600 s replica timeout; the Registrar App's key uploaded to Key Vault ([BOOTSTRAP](../BOOTSTRAP.md)); [the smoke test](../../examples/target-repository/.github/workflows/smoke-test.yml) in the private target repository.

## Steps

1. Queue the smoke test, then `az containerapp job start`.
2. Read the execution's console logs (JSON phases) and system logs in Log Analytics.
3. The smoke test's identity step: the endpoint without its header, and every process's environment searched with `sudo`.
4. Two executions with a template override (REST `start`): one printing the identity endpoint's URL (not its header), one running Podman's official image (`quay.io/podman/stable`).

## Result

1. The execution started at 20:11:11 UTC; the container at 20:11:40 (scheduling and the image pull: **15 s** for 775 MB compressed); the key read from Key Vault in 1.5 s; the runner (`job-runner-runners-dev-x6gt4h8-7aff49`, named after the execution) started at 20:11:43; the job ran from 20:11:47 to 20:11:53. **36 s** from the start to the job; the execution *Succeeded* after 48 s; no runner left in the repository.
2. Console logs: `start`, `kv_read`, `jwt`, `install_token`, `jitconfig`, `run`, in order, without secrets.
3. The identity endpoint is `http://localhost:12356/msi/token`. From a job step, without its header: **HTTP 403**. No process's environment holds the header (searched as root). The step passed.
4. Podman cannot run in the job: no `/dev/fuse`; user namespaces refused (`unshare: Operation not permitted`), so no rootless mode; as root, `Cgroups v1 not supported` with overlay and vfs storage alike (Podman 6.1.3).

A container that exits within a fraction of a second loses its console output: the log collector misses it. Probes keep running for 30 s.

## Conclusion

Phase 3 is done: on Container Apps, an execution registers one runner from the Key Vault key, runs one job and leaves; a step can reach the identity endpoint but gets nothing without the header, which no process keeps. A job needing Docker or Podman stays on GitHub-hosted runners ([D13](../DECISIONS.md)). Next: the event trigger (Phase 4), which needs the Scaler App.

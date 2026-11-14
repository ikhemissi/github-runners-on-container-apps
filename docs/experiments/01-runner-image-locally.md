# 01 — The runner image and its entrypoint, locally

**Date:** 2026-11-14 · **Answers:** Q2 (offline part) · **Versions:** runner 2.338.2 (`ghcr.io/actions/actions-runner`, index `sha256:6d0b2d80…c31300`), Azure CLI 2.92.0, GitHub CLI 2.104.0, Node 26.13.1, Podman 4.9.3, hadolint 2.15.1, GitHub REST API 2026-03-10

## Goal

The image builds from pinned inputs, holds no secret, and its entrypoint registers one JIT runner without leaking a secret to the runner, its job or the logs. Done when lint is clean, the offline tests pass, and a runner started from a laptop runs `smoke-test.yml`.

## Setup

Podman on Linux. No Azure resource; for the last step, a private repository and the Registrar App ([runner/README.md](../../runner/README.md#local-test-mode-one-runner-from-your-machine)).

## Steps

1. `make lint`: shellcheck on the scripts, hadolint on the Dockerfile.
2. `make test`: builds the image, starts the added tools, runs [the entrypoint's tests](../../runner/tests/test-entrypoint.sh) against fakes of the managed identity endpoint, Key Vault and GitHub.
3. Secret scan of the image: `trivy image --scanners secret` on the saved image, and `podman history`.
4. Local test mode against a private repository: `make run-local`, then `smoke-test.yml`.

## Result

1. Lint clean, after two hadolint fixes: numeric `USER`s, and no unpinned `apt-get install` (the base image already has `ca-certificates` and `gpg`).
2. 23 checks pass: the JWT verifies with the public key (RS256, issuer the client ID, `iat` 60 s back, `exp` within 10 minutes); the installation token is requested for the one repository with Administration: write only; the JIT request carries the labels, group 1, `_work` and a name starting with the execution name; GitHub calls send API version 2026-03-10; the runner's environment has none of the sensitive variables; the logs hold no token, key or JIT configuration and list the phases in order; in Azure mode the identity endpoint is called with the `runtime` client ID and the Key Vault resource, and Key Vault with the identity's token; a missing setting exits 1 before any call; a GitHub 500 is tried 3 times, then exits 3 without starting the runner.
   The tool check caught Node failing to start (`libatomic.so.1` missing from the base image): fixed by installing `libatomic1`.
3. Trivy: 0 secrets. The image is 2.5 GB (the official image 1.6 GB).
4. With the Registrar App (Administration: read and write, Metadata: read, installed on one private repository), `make run-local` registered runner `cb47e4f8fbb1-2a8969`, listed online and idle, with the single label `aca-agent` and none of the default `self-hosted`, `Linux`, `X64` labels ([D9](../DECISIONS.md)). The smoke test (`runs-on: aca-agent`, manual trigger) ran on it in **10 s** (17:18:10 → 17:18:20 UTC): it showed the runner (Linux, X64) and its tools (Azure CLI 2.92.0, GitHub CLI 2.104.0, Node 26.13.1), and found none of the entrypoint's sensitive variables in the step's environment. The container then exited, and the repository's runner list was **empty**.

## Conclusion

Phase 1 is done: a JIT runner registered with a GitHub App's installation token ran exactly one job, kept the secrets out of it, then left the repository. Still to show on Azure: the Key Vault path with a real managed identity, the identity endpoint seen from a step (Q5), and the start-up time of an execution (Q8).

# The runner image

The official GitHub Actions runner image (pinned by digest) with the Azure CLI, the GitHub CLI and Node LTS, and [entrypoint.sh](entrypoint.sh), which registers **one just-in-time runner** for one repository and runs **one job**:

1. reads the Registrar App's private key from Key Vault with the job's managed identity;
2. signs a GitHub App JWT and exchanges it for an installation token limited to the repository and to Administration: write;
3. asks GitHub for a JIT runner configuration (`generate-jitconfig`);
4. clears every sensitive variable and replaces itself with the runner, which runs one job and exits.

Logs are JSON lines on stderr (`phase`: `start`, `kv_read`, `jwt`, `install_token`, `jitconfig`, `run`, `exit`). Exit codes: 1 settings, 2 Azure, 3 GitHub.

## Settings

| Variable | Meaning |
|---|---|
| `GH_OWNER`, `GH_REPO` | The repository the runner serves |
| `GH_REGISTRAR_CLIENT_ID` | The Registrar App's client ID (its settings page) |
| `GH_REGISTRAR_INSTALLATION_ID` | Its installation on the repository: the number at the end of the installation's settings URL |
| `RUNNER_LABELS` | Comma-separated labels, e.g. `aca-agent` |
| `RUNNER_GROUP_ID` | The runner group; `1` is the repository's default group |
| `KV_SECRET_URI_REGISTRAR` | The key's Key Vault secret, without version: `https://<vault>.vault.azure.net/secrets/<name>` |
| `AZURE_CLIENT_ID_RUNTIME` | The client ID of the job's `runtime` identity |
| `GH_REGISTRAR_KEY_FILE` | Local test mode only: the key's file, instead of Key Vault and the managed identity |

Container Apps sets `IDENTITY_ENDPOINT`, `IDENTITY_HEADER` and `CONTAINER_APP_JOB_EXECUTION_NAME` (the runner's name starts with it).

## Checks

```bash
make lint   # shellcheck and hadolint
make test   # builds the image, starts its tools, and runs the entrypoint's offline tests in it
```

The tests ([tests/test-entrypoint.sh](tests/test-entrypoint.sh)) run the entrypoint against a fake of the managed identity endpoint, Key Vault and GitHub ([tests/fake_services.py](tests/fake_services.py)) and a stub `run.sh`. They check the JWT's signature and claims, the token's scope, the runner's labels, group and name, that no sensitive variable reaches the runner and no secret reaches the logs, the exit codes, and the retries.

## Local test mode: one runner from your machine

Registers a real JIT runner on the target repository, without Azure. The repository must be **private**.

1. **Create the Registrar App** (GitHub → Settings → Developer settings → GitHub Apps → New): no webhook, repository permissions **Administration: Read and write** and **Metadata: Read**, nothing else. Install it on the target repository only. Note its client ID and the installation ID.
2. **Generate a private key** for it (the App's settings page); keep the `.pem` outside the repository.
3. **Write `runner/.env`** (git-ignored):

   ```bash
   GH_OWNER=<owner>
   GH_REPO=<private repository>
   GH_REGISTRAR_CLIENT_ID=<client ID>
   GH_REGISTRAR_INSTALLATION_ID=<installation ID>
   RUNNER_LABELS=aca-agent
   RUNNER_GROUP_ID=1
   ```

4. **Start one runner:** `make run-local GH_REGISTRAR_KEY_FILE=/path/to/registrar.pem`. It appears under the repository's Settings → Actions → Runners, idle.
5. **Run a job on it:** copy [smoke-test.yml](../examples/target-repository/.github/workflows/smoke-test.yml) into the target repository and run it (Actions → *Smoke test of the ephemeral runners* → Run workflow). The runner takes the job, then exits and disappears from the list.

Container actions and `services:` don't work on these runners: the image has no Docker daemon.

# Bootstrap

Everything to set up by hand, in order. Steps marked *(Phase n)* come with that phase.

## 1. Azure environment (Phase 2)

Signed in with the Azure CLI (`az login`) and azd to the target tenant. If azd's default sign-in is another tenant, give this project an azd profile that uses the Azure CLI's sign-in: `export AZD_CONFIG_DIR=~/.azd-<tenant>` and `azd config set auth.useAzCliAuth true` once in it.

```bash
azd env new runners-dev --subscription "$(az account show --query id -o tsv)" --location francecentral
azd env set RESOURCE_TAGS "key=value,key=value"   # tags your tenant's policies require, if any
azd hooks run preprovision                        # the Terraform state backend, once
azd provision --preview                           # read the plan: only adds the first time
azd provision
```

Optional settings: `RUNNER_DEPLOYER_SCOPE` (the resource group workflow steps may act on; default this project's) and `RUNNER_DEPLOYER_ROLE` (default `Reader`).

## 2. GitHub Apps

Create each App under GitHub → Settings → Developer settings → GitHub Apps → New GitHub App: homepage URL this repository, no callback URL, **webhook inactive**, installable **only on this account**. Install it on the private target repository only (*Only select repositories*). Note its **client ID** (settings page), its **App ID**, and the **installation ID** (the number at the end of the installation's settings URL).

| App | Repository permissions | Used by |
|---|---|---|
| Registrar | Administration: Read and write; Metadata: Read-only | the entrypoint, to create JIT runners |
| Scaler *(Phase 4)* | Actions: Read-only; Metadata: Read-only | the KEDA scaler, to count queued jobs |

Generate a private key for each (the App's settings page) and keep the `.pem` files outside any repository, readable only by you.

## 3. Upload the keys to Key Vault

Terraform created both secrets with a placeholder, so that the runner identity's roles cover exactly these two secrets; uploading a key adds a new version.

```bash
vault=$(azd env get-value KEY_VAULT_NAME)
az keyvault secret set --vault-name "$vault" --name "$(azd env get-value RUNNER_REGISTRAR_KEY_SECRET_NAME)" \
  --file /path/to/registrar.pem --content-type application/x-pem-file -o none
az keyvault secret set --vault-name "$vault" --name "$(azd env get-value RUNNER_SCALER_KEY_SECRET_NAME)" \
  --file /path/to/scaler.pem --content-type application/x-pem-file -o none   # Phase 4
shred -u /path/to/registrar.pem   # once the runners work from Key Vault
```

Your own account writes the secrets as *Key Vault Secrets Officer* (granted by Terraform to the deployer).

**Key rotation:** generate a second key in the App's settings, upload it as above (a new version), check that a job still runs, then delete the old key in GitHub. Both Apps accept several active keys.

## 4. Azure sign-in from workflows (Phase 5)

1. In the target repository, create the environment and its variables (not secrets), and accept the `main` branch only:

   ```bash
   repo=<owner>/<repository>
   gh api -X PUT repos/$repo/environments/azure-dev
   gh variable set AZURE_CLIENT_ID --repo $repo --env azure-dev --body "$(azd env get-value RUNNER_DEPLOYER_CLIENT_ID)"
   gh variable set AZURE_TENANT_ID --repo $repo --env azure-dev --body "$(azd env get-value AZURE_TENANT_ID)"
   gh variable set AZURE_SUBSCRIPTION_ID --repo $repo --env azure-dev --body "$(azd env get-value AZURE_SUBSCRIPTION_ID)"
   ```

2. Copy [print-oidc-claims.yml](../examples/target-repository/.github/workflows/print-oidc-claims.yml) and the [smoke test](../examples/target-repository/.github/workflows/smoke-test.yml) into it, and run *OIDC token claims*. If `sub` differs from `azd env get-value RUNNER_OIDC_SUBJECT_IN_USE` (repositories may use the format with immutable IDs), `azd env set RUNNER_DEPLOYER_OIDC_SUBJECT "<sub>"` and `azd provision`.
3. Run the smoke test: its last step shows the subscription, signed in without a secret.
4. Restrict the environment to `main` (Settings → Environments → azure-dev → Deployment branches).

## 5. Budget (Phase 6)

`azd env set BUDGET_AMOUNT <amount per month>` then `azd provision`: alerts go to the resource group's Owners.

## 6. Images and egress control (Phase 6)

The images are built in the project's registry (ACR Tasks: no local container engine needed), tagged with the current commit:

```bash
make push-runner && azd env set RUNNER_IMAGE_TAG "$(git rev-parse --short HEAD)"
make push-proxy && azd env set EGRESS_PROXY_IMAGE_TAG "$(git rev-parse --short HEAD)"
azd env set EGRESS_PROXY true
azd provision --preview   # the first time: the runners' environment and job are replaced (about 25 min); no job may be running
azd provision
```

Then run the smoke test: its egress step checks that an allowlisted domain answers, another is refused, and the internet can't be reached without the proxy.

**The allowlist:** when a workflow fails on a download, the proxy's log shows the domain it was denied ([OPERATIONS](OPERATIONS.md), query 6). Add it to [allowlist.txt](../egress-proxy/allowlist.txt) under the tool that needs it, `make test-proxy`, commit, then `make push-proxy`, set `EGRESS_PROXY_IMAGE_TAG` and `azd provision` (an in-place update of the proxy).

**Private networking:** `azd env set PRIVATE_NETWORKING true`, preview, provision: Key Vault gets a private endpoint (D21).

**Tenant policies:** if your tenant's policies change resources that lack some tags, set them in `RESOURCE_TAGS` before the first provision. Every provision re-applies them, and public network access, to the Terraform state account.

## 7. The Copilot cloud agent (optional)

1. In the target repository's `.github/workflows/copilot-setup-steps.yml`: `runs-on: aca-agent`, and the setup action of any tool the runner image lacks (`actions/setup-go`). Run the workflow once by hand on the runners before merging.
2. Make sure the allowlist covers the agent's hosts (`.githubcopilot.com`) and the hosts of the MCP servers the repository declares (`.mcp.json`).
3. Turn off the agent's integrated firewall: repository Settings → Copilot → Cloud agent.
4. Start each session with Environment → **Actions**; then check the proxy's denied requests ([OPERATIONS](OPERATIONS.md)).

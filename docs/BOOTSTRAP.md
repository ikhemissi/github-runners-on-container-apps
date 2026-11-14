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

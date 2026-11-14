# The runners' identities and their access (PRD-001, F4 and F5). Phase 2: no federated credential yet (Phase 5).
# - runtime: attached to the runner job; pulls the image and reads the two GitHub App keys, nothing else.
# - deployer: never attached to the job; workflow steps will sign in as it through GitHub OIDC.
# The two keys are Key Vault secrets created here with a placeholder (write-only: never in the state), so that the
# runtime identity's roles can be scoped to them; the real keys are uploaded by hand (docs/BOOTSTRAP.md).

variable "runner_deployer_scope" {
  description = "Resource group the deployer identity may act on (RUNNER_DEPLOYER_SCOPE, a resource ID). Empty: this project's resource group."
  type        = string
}

variable "runner_deployer_role" {
  description = "Its role there (RUNNER_DEPLOYER_ROLE), e.g. Reader or Contributor."
  type        = string
}

locals {
  runner_key_secrets = {
    scaler    = "github-app-scaler-key"
    registrar = "github-app-registrar-key"
  }
  runner_deployer_scope = coalesce(var.runner_deployer_scope, azurerm_resource_group.main.id)
}

resource "azurerm_user_assigned_identity" "runner_runtime" {
  name                = "id-runner-runtime-${var.environment_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "runner_deployer" {
  name                = "id-runner-deployer-${var.environment_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_key_vault_secret" "runner_keys" {
  for_each         = local.runner_key_secrets
  name             = each.value
  key_vault_id     = module.key_vault.id
  content_type     = "application/x-pem-file"
  value_wo         = "placeholder: upload the GitHub App's private key (docs/BOOTSTRAP.md)"
  value_wo_version = 1
  tags             = local.tags
}

resource "azurerm_role_assignment" "runner_runtime_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.runner_runtime.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "runner_runtime_keys" {
  for_each             = azurerm_key_vault_secret.runner_keys
  scope                = each.value.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runner_runtime.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "runner_deployer" {
  scope                = local.runner_deployer_scope
  role_definition_name = var.runner_deployer_role
  principal_id         = azurerm_user_assigned_identity.runner_deployer.principal_id
  principal_type       = "ServicePrincipal"
}

output "RUNNER_RUNTIME_IDENTITY_ID" { value = azurerm_user_assigned_identity.runner_runtime.id }
output "RUNNER_RUNTIME_CLIENT_ID" { value = azurerm_user_assigned_identity.runner_runtime.client_id }
output "RUNNER_DEPLOYER_CLIENT_ID" { value = azurerm_user_assigned_identity.runner_deployer.client_id }
output "RUNNER_SCALER_KEY_SECRET_NAME" { value = local.runner_key_secrets.scaler }
output "RUNNER_REGISTRAR_KEY_SECRET_NAME" { value = local.runner_key_secrets.registrar }
output "RUNNER_REGISTRAR_KEY_SECRET_URI" { value = azurerm_key_vault_secret.runner_keys["registrar"].versionless_id }
output "RUNNER_SCALER_KEY_SECRET_URI" { value = azurerm_key_vault_secret.runner_keys["scaler"].versionless_id }

# Workflow steps sign in to Azure as the deployer identity through GitHub OIDC (PRD-001, F6), without any secret:
# the identity trusts tokens of one GitHub environment of the target repository. The token's subject format depends
# on the repository's OIDC settings: check it with the smoke test's claims step, and set RUNNER_DEPLOYER_OIDC_SUBJECT
# when it differs from the default.

variable "runner_oidc_environment" {
  description = "The GitHub environment whose tokens the deployer identity trusts (RUNNER_OIDC_ENVIRONMENT)."
  type        = string
}

variable "runner_deployer_oidc_subject" {
  description = "The token's exact subject (RUNNER_DEPLOYER_OIDC_SUBJECT). Empty: repo:<owner>/<repository>:environment:<environment>."
  type        = string
}

locals {
  runner_deployer_oidc_subject = coalesce(
    var.runner_deployer_oidc_subject,
    "repo:${var.runner_github_owner}/${var.runner_github_repo}:environment:${var.runner_oidc_environment}"
  )
}

# Azure rejects concurrent writes of federated credentials on one identity: a second one must depend on this one.
resource "azurerm_federated_identity_credential" "runner_deployer" {
  name                      = "github-${var.runner_oidc_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.runner_deployer.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = local.runner_deployer_oidc_subject
}

output "RUNNER_OIDC_SUBJECT_IN_USE" { value = local.runner_deployer_oidc_subject }

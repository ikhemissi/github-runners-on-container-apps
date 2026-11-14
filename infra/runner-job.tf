# The runner job (PRD-001, F2, F7, F9): each execution registers one just-in-time runner that runs one job, then
# exits. Phase 3 starts executions by hand (manual trigger); Phase 4 switches to the event trigger with the KEDA
# github-runner rule, which replaces the job (a trigger type can't change in place).

variable "runner_image_tag" {
  description = "Tag of the runner image in the project's registry (RUNNER_IMAGE_TAG), e.g. the commit it was built from."
  type        = string
}

variable "runner_github_owner" {
  description = "Owner of the repository the runners serve (RUNNER_GITHUB_OWNER)."
  type        = string
}

variable "runner_github_repo" {
  description = "That repository (RUNNER_GITHUB_REPO); it must be private."
  type        = string
}

variable "runner_registrar_client_id" {
  description = "The Registrar App's client ID (RUNNER_REGISTRAR_CLIENT_ID)."
  type        = string
}

variable "runner_registrar_installation_id" {
  description = "Its installation ID on the repository (RUNNER_REGISTRAR_INSTALLATION_ID)."
  type        = string
}

variable "runner_labels" {
  description = "The runners' labels, comma-separated (RUNNER_LABELS); workflows request them with runs-on."
  type        = string
}

variable "runner_group_id" {
  description = "The runner group (RUNNER_GROUP_ID); 1 is the repository's default group."
  type        = number
}

variable "runner_cpu" {
  description = "vCPUs of an execution (RUNNER_CPU), 0.25 to 4 in steps of 0.25."
  type        = number

  validation {
    condition     = var.runner_cpu >= 0.25 && var.runner_cpu <= 4 && floor(var.runner_cpu * 4) == var.runner_cpu * 4
    error_message = "runner_cpu must be 0.25 to 4, in steps of 0.25 (Consumption profile)."
  }
}

variable "runner_replica_timeout_in_seconds" {
  description = "Longest an execution may run (RUNNER_REPLICA_TIMEOUT), above the longest job's timeout-minutes."
  type        = number
}

locals {
  # Consumption profile: memory is twice the vCPUs.
  runner_memory = "${var.runner_cpu * 2}Gi"
}

resource "azurerm_container_app_job" "runner" {
  name                         = "job-runner-${var.environment_name}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  container_app_environment_id = module.container_apps_environment.id
  replica_timeout_in_seconds   = var.runner_replica_timeout_in_seconds
  # A retried execution would register a second runner for the same queued job.
  replica_retry_limit = 0
  tags                = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runner_runtime.id]
  }

  registry {
    server   = module.container_registry.login_server
    identity = azurerm_user_assigned_identity.runner_runtime.id
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "runner"
      image  = "${module.container_registry.login_server}/gh-runner:${var.runner_image_tag}"
      cpu    = var.runner_cpu
      memory = local.runner_memory

      env {
        name  = "GH_OWNER"
        value = var.runner_github_owner
      }
      env {
        name  = "GH_REPO"
        value = var.runner_github_repo
      }
      env {
        name  = "GH_REGISTRAR_CLIENT_ID"
        value = var.runner_registrar_client_id
      }
      env {
        name  = "GH_REGISTRAR_INSTALLATION_ID"
        value = var.runner_registrar_installation_id
      }
      env {
        name  = "RUNNER_LABELS"
        value = var.runner_labels
      }
      env {
        name  = "RUNNER_GROUP_ID"
        value = tostring(var.runner_group_id)
      }
      env {
        name  = "KV_SECRET_URI_REGISTRAR"
        value = azurerm_key_vault_secret.runner_keys["registrar"].versionless_id
      }
      env {
        name  = "AZURE_CLIENT_ID_RUNTIME"
        value = azurerm_user_assigned_identity.runner_runtime.client_id
      }
    }
  }

  # The first execution needs the image pull and the key's read to work.
  depends_on = [azurerm_role_assignment.runner_runtime_pull, azurerm_role_assignment.runner_runtime_keys]
}

output "RUNNER_JOB_NAME" { value = azurerm_container_app_job.runner.name }

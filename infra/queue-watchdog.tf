# The queue watchdog (docs/DECISIONS.md D26): a Flex Consumption function app (src/QueueWatchdog, azd service
# "watchdog") that starts runner executions for jobs the scale rule's scaler left waiting. Every 5 minutes it lists
# each watched repository's unfinished runs as the Scaler App (Actions: read, its key read from Key Vault) and starts
# what StartDecision says. Its identity holds one custom role, on the runner jobs only: read them and their
# executions, and start an execution. It runs outside the runners' network, so the egress proxy doesn't apply to it.

variable "queue_watchdog_stuck_after_in_seconds" {
  description = "How long a job may stay queued before the watchdog starts an execution for it (QUEUE_WATCHDOG_STUCK_AFTER): longer than the scaler takes (about a minute), so that the two rarely start one for the same job."
  type        = number

  validation {
    condition     = var.queue_watchdog_stuck_after_in_seconds >= 120
    error_message = "queue_watchdog_stuck_after_in_seconds must be at least 120: the scaler needs about a minute to start an execution."
  }
}

resource "azurerm_role_definition" "queue_watchdog" {
  name        = "Runner queue watchdog (${var.environment_name}-${local.token})"
  description = "Reads the runner jobs and their executions, and starts an execution."
  scope       = azurerm_resource_group.main.id

  permissions {
    actions = [
      "Microsoft.App/jobs/read",
      "Microsoft.App/jobs/executions/read",
      "Microsoft.App/jobs/start/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.main.id]
}

module "queue_watchdog_storage" {
  source              = "./modules/storage-account"
  name                = "st${local.compact_name}wd${local.token}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  tags                = local.tags
}

locals {
  # The repository=job pairs the watchdog checks (RUNNER_JOBS): every runner job.
  queue_watchdog_runner_jobs = join(",", [for job in values(local.runner_jobs) : "${job.repo}=${job.name}"])
  queue_watchdog_job_roles = {
    for key, job in azurerm_container_app_job.runner :
    "runner-job-${key}" => { scope = job.id, role = azurerm_role_definition.queue_watchdog.name }
  }
}

module "queue_watchdog" {
  source                    = "./modules/function-app-flex"
  name                      = "func-watchdog-${var.environment_name}-${local.token}"
  plan_name                 = "asp-watchdog-${var.environment_name}"
  resource_group_id         = azurerm_resource_group.main.id
  resource_group_name       = azurerm_resource_group.main.name
  location                  = var.location
  tags                      = local.tags
  azd_service_name          = "watchdog"
  storage_account_id        = module.queue_watchdog_storage.id
  storage_account_name      = module.queue_watchdog_storage.name
  storage_blob_endpoint     = module.queue_watchdog_storage.primary_blob_endpoint
  deployment_container_name = "watchdog-package"
  runtime_name              = "dotnet-isolated"
  runtime_version           = "10.0"
  instance_memory_mb        = 512
  maximum_instance_count    = 1

  app_settings = {
    SUBSCRIPTION_ID     = var.subscription_id
    RESOURCE_GROUP_NAME = azurerm_resource_group.main.name
    GITHUB_OWNER        = var.runner_github_owner
    RUNNER_JOBS         = local.queue_watchdog_runner_jobs
    RUNNER_LABELS       = var.runner_labels
    # The scale rule's own maximum, per runner job.
    RUNNER_MAX_EXECUTIONS  = tostring(var.runner_max_executions)
    STUCK_AFTER_SECONDS    = tostring(var.queue_watchdog_stuck_after_in_seconds)
    SCALER_APP_ID          = var.runner_scaler_app_id
    SCALER_INSTALLATION_ID = var.runner_scaler_installation_id
    SCALER_KEY_SECRET_URI  = azurerm_key_vault_secret.runner_keys["scaler"].versionless_id
  }

  application_insights_connection_string = module.monitoring.application_insights_connection_string
  role_assignments = merge(local.queue_watchdog_job_roles, {
    telemetry  = { scope = module.monitoring.application_insights_id, role = "Monitoring Metrics Publisher" }
    scaler_key = { scope = azurerm_key_vault_secret.runner_keys["scaler"].resource_versionless_id, role = "Key Vault Secrets User" }
  })
}

output "QUEUE_WATCHDOG_NAME" { value = module.queue_watchdog.name }

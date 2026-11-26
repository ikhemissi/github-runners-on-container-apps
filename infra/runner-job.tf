# The runner job (PRD-001, F2, F7, F8, F9): the KEDA github-runner rule starts one execution per queued job with the
# runners' labels; each execution registers one just-in-time runner that runs that job, then exits. Nothing queued:
# nothing runs. (Changing a job's trigger type replaces the job.)

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

variable "runner_extra_repos" {
  description = "More private repositories of the same owner to serve, one job each, as comma-separated key=repository pairs (RUNNER_EXTRA_REPOS), e.g. \"mods=my-modules,app=my-app\"; the key (letters and digits, 6 at most) ends the job's name. The two GitHub Apps must be installed on them. Empty: none."
  type        = string
  default     = ""

  validation {
    condition     = alltrue([for pair in split(",", var.runner_extra_repos) : trimspace(pair) == "" || can(regex("^[a-z0-9]{1,6}=[A-Za-z0-9._-]+$", trimspace(pair)))])
    error_message = "runner_extra_repos must be comma-separated key=repository pairs, keys of 1 to 6 lowercase letters or digits."
  }
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

variable "runner_scaler_app_id" {
  description = "The Scaler App's App ID, the number on its settings page (RUNNER_SCALER_APP_ID); KEDA needs it, not the client ID."
  type        = string
}

variable "runner_scaler_installation_id" {
  description = "Its installation ID on the repository (RUNNER_SCALER_INSTALLATION_ID)."
  type        = string
}

variable "runner_max_executions" {
  description = "Most executions at once (RUNNER_MAX_EXECUTIONS): more queued jobs wait for a free one."
  type        = number
}

variable "runner_polling_interval_in_seconds" {
  description = "How often KEDA asks GitHub for queued jobs (RUNNER_POLLING_INTERVAL)."
  type        = number
}

variable "runner_idle_timeout_in_seconds" {
  description = "How long a runner waits for a job before it removes itself (RUNNER_IDLE_TIMEOUT): the scaler can start more executions than there are jobs (docs/DECISIONS.md, D15)."
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

  # One job per repository: the KEDA rule and the runner's registration each serve one repository (runnerScope=repo).
  # The first repository keeps the job's original name.
  runner_extra_repo_pairs = [for pair in split(",", var.runner_extra_repos) : split("=", trimspace(pair)) if trimspace(pair) != ""]
  runner_jobs = merge(
    { main = { repo = var.runner_github_repo, name = "job-runner-${var.environment_name}" } },
    { for pair in local.runner_extra_repo_pairs : pair[0] => { repo = pair[1], name = "job-runner-${var.environment_name}-${pair[0]}" } },
  )
}

# The job became one per repository: the existing job is the "main" one, not a new one.
moved {
  from = azurerm_container_app_job.runner
  to   = azurerm_container_app_job.runner["main"]
}

resource "azurerm_container_app_job" "runner" {
  for_each                     = local.runner_jobs
  name                         = each.value.name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  container_app_environment_id = module.container_apps_environment.id
  # The environment has workload profiles: the service sets this one, so the plan stays clean.
  workload_profile_name      = "Consumption"
  replica_timeout_in_seconds = var.runner_replica_timeout_in_seconds
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

  # The Scaler App's key, read from Key Vault by the runtime identity; only KEDA uses it, never the container.
  secret {
    name                = "github-app-scaler-key"
    key_vault_secret_id = azurerm_key_vault_secret.runner_keys["scaler"].versionless_id
    identity            = azurerm_user_assigned_identity.runner_runtime.id
  }

  event_trigger_config {
    parallelism              = 1
    replica_completion_count = 1

    scale {
      min_executions              = 0
      max_executions              = var.runner_max_executions
      polling_interval_in_seconds = var.runner_polling_interval_in_seconds

      rules {
        name             = "github-runner"
        custom_rule_type = "github-runner"
        metadata = {
          owner           = var.runner_github_owner
          runnerScope     = "repo"
          repos           = each.value.repo
          labels          = var.runner_labels
          noDefaultLabels = "true"
          # Off: with ETags the scaler kept counting a completed run (docs/DECISIONS.md, D15).
          enableEtags               = "false"
          targetWorkflowQueueLength = "1"
          applicationID             = var.runner_scaler_app_id
          installationID            = var.runner_scaler_installation_id
        }

        authentication {
          secret_name       = "github-app-scaler-key"
          trigger_parameter = "appKey"
        }
      }
    }
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
        value = each.value.repo
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
        name  = "RUNNER_IDLE_TIMEOUT"
        value = tostring(var.runner_idle_timeout_in_seconds)
      }
      env {
        name  = "KV_SECRET_URI_REGISTRAR"
        value = azurerm_key_vault_secret.runner_keys["registrar"].versionless_id
      }
      env {
        name  = "AZURE_CLIENT_ID_RUNTIME"
        value = azurerm_user_assigned_identity.runner_runtime.client_id
      }
      # With the egress proxy, its address for the runner and the steps (egress-proxy.tf); none otherwise.
      dynamic "env" {
        for_each = local.runner_proxy_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  # The first execution needs the image pull and the key's read to work.
  depends_on = [azurerm_role_assignment.runner_runtime_pull, azurerm_role_assignment.runner_runtime_keys]
}

output "RUNNER_JOB_NAME" { value = azurerm_container_app_job.runner["main"].name }
output "RUNNER_EXTRA_JOB_NAMES" { value = join(",", [for key, job in azurerm_container_app_job.runner : job.name if key != "main"]) }

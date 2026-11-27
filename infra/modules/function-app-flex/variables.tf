variable "name" {
  description = "Function app name (globally unique: <name>.azurewebsites.net)."
  type        = string
}

variable "plan_name" {
  description = "Flex Consumption plan name: one plan per app."
  type        = string
}

variable "resource_group_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  description = "A region where Flex Consumption is available (az functionapp list-flexconsumption-locations)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "azd_service_name" {
  description = "The service's name in azure.yaml (host: function)."
  type        = string
}

variable "storage_account_id" {
  description = "Storage account for the Functions host and the deployment package (shared keys may be disabled)."
  type        = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_blob_endpoint" {
  description = "The account's primary blob endpoint, with its trailing slash (https://<account>.blob.core.windows.net/)."
  type        = string
}

variable "deployment_container_name" {
  description = "Blob container for the app's deployment package, created here (3-63 lowercase letters, digits, hyphens)."
  type        = string
}

variable "runtime_name" {
  description = "dotnet-isolated, python, node, java, powershell or custom."
  type        = string
}

variable "runtime_version" {
  description = "A version the runtime supports on Flex Consumption, e.g. 3.12 for python, 9.0 for dotnet-isolated."
  type        = string
}

variable "instance_memory_mb" {
  description = "Instance memory: 512, 2048 (the usual default) or 4096 MB."
  type        = number
  default     = 2048

  validation {
    condition     = contains([512, 2048, 4096], var.instance_memory_mb)
    error_message = "instance_memory_mb must be 512, 2048 or 4096."
  }
}

variable "maximum_instance_count" {
  description = "Maximum number of on-demand instances (1 to 1000), applied per function group."
  type        = number
  default     = 40

  validation {
    condition     = var.maximum_instance_count >= 1 && var.maximum_instance_count <= 1000
    error_message = "maximum_instance_count must be between 1 and 1000."
  }
}

variable "app_settings" {
  description = "The app's own settings (no secrets; use Key Vault references). Host storage and telemetry settings are added."
  type        = map(string)
  default     = {}
}

variable "application_insights_connection_string" {
  description = "Telemetry with Entra authentication; give the identity Monitoring Metrics Publisher on the resource too (role_assignments). A .NET isolated worker also passes the credential to its exporter in code (knowledge: functions-worker-exporter-needs-entra-credential). Null: no telemetry."
  type        = string
  default     = null
  sensitive   = true
}

variable "role_assignments" {
  description = "Further roles of the app's identity, by a name of your choice: the scope and the role name."
  type = map(object({
    scope = string
    role  = string
  }))
  default = {}
}

variable "subnet_id" {
  description = "A subnet delegated to Microsoft.App/environments for virtual network integration. Null: none."
  type        = string
  default     = null
}

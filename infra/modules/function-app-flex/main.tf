# A function app on the Flex Consumption plan (one app per plan), for a service that azd deploys (azure.yaml,
# host: function): its own user-assigned identity, whose roles exist before the app starts; host storage and the
# deployment package reached with that identity (no storage keys); telemetry to Application Insights with Entra
# authentication. The plan and the app are created with azapi, as in Microsoft's Flex Consumption templates: azurerm's
# function_app_flex_consumption writes an AzureWebJobsStorage connection string that overrides identity-based host
# storage (knowledge: azurerm-flex-consumption-identity-host-storage).

locals {
  api_version = "2024-04-01"
  # Host storage through the app's identity (no AzureWebJobsStorage connection string).
  identity_storage_settings = {
    AzureWebJobsStorage__accountName = var.storage_account_name
    AzureWebJobsStorage__credential  = "managedidentity"
    AzureWebJobsStorage__clientId    = azurerm_user_assigned_identity.app.client_id
    AZURE_CLIENT_ID                  = azurerm_user_assigned_identity.app.client_id
  }
  # Whether a connection string was given is not secret, unlike the string itself.
  sends_telemetry = nonsensitive(var.application_insights_connection_string != null)
  telemetry_settings = local.sends_telemetry ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING     = var.application_insights_connection_string
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "ClientId=${azurerm_user_assigned_identity.app.client_id};Authorization=AAD"
  } : {}
  app_settings = merge(var.app_settings, local.identity_storage_settings, local.telemetry_settings)
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Host storage (blobs, queues and tables of the Functions host) and the deployment package.
resource "azurerm_role_assignment" "host_storage" {
  for_each             = toset(["Storage Blob Data Owner", "Storage Queue Data Contributor", "Storage Table Data Contributor"])
  scope                = var.storage_account_id
  role_definition_name = each.key
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app" {
  for_each             = var.role_assignments
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

# The deployment package's container: azd uploads the zipped app there, and the app reads it with its identity.
resource "azurerm_storage_container" "deployment" {
  name               = var.deployment_container_name
  storage_account_id = var.storage_account_id
}

resource "azapi_resource" "plan" {
  type      = "Microsoft.Web/serverfarms@${local.api_version}"
  name      = var.plan_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  body = {
    kind = "functionapp"
    sku = {
      tier = "FlexConsumption"
      name = "FC1"
    }
    properties = {
      reserved = true
    }
  }
}

resource "azapi_resource" "app" {
  type      = "Microsoft.Web/sites@${local.api_version}"
  name      = var.name
  parent_id = var.resource_group_id
  location  = var.location
  # azd finds the app of a service through this tag.
  tags = merge(var.tags, { "azd-service-name" = var.azd_service_name })

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  body = {
    kind = "functionapp,linux"
    properties = {
      serverFarmId           = azapi_resource.plan.id
      httpsOnly              = true
      virtualNetworkSubnetId = var.subnet_id
      siteConfig = {
        minTlsVersion = "1.2"
        appSettings   = [for name, value in local.app_settings : { name = name, value = value }]
      }
      functionAppConfig = {
        deployment = {
          storage = {
            type  = "blobContainer"
            value = "${var.storage_blob_endpoint}${azurerm_storage_container.deployment.name}"
            authentication = {
              type                           = "UserAssignedIdentity"
              userAssignedIdentityResourceId = azurerm_user_assigned_identity.app.id
            }
          }
        }
        scaleAndConcurrency = {
          maximumInstanceCount = var.maximum_instance_count
          instanceMemoryMB     = var.instance_memory_mb
        }
        runtime = {
          name    = var.runtime_name
          version = var.runtime_version
        }
      }
    }
  }

  # Leaves out the properties set to null (e.g. no virtual network) instead of sending them.
  ignore_null_property   = true
  response_export_values = ["properties.defaultHostName"]

  depends_on = [azurerm_role_assignment.host_storage, azurerm_role_assignment.app]
}

# The app reaches its storage and sends telemetry with its own identity: no storage key, no deprecated settings.

mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-func-test"
      client_id    = "00000000-0000-0000-0000-000000000003"
      principal_id = "00000000-0000-0000-0000-000000000004"
    }
  }
}

mock_provider "azapi" {
  override_during = plan

  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Web/sites/func-test"
      output = { properties = { defaultHostName = "func-test.azurewebsites.net" } }
    }
  }
}

variables {
  name                      = "func-test"
  plan_name                 = "plan-func-test"
  resource_group_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  resource_group_name       = "rg-test"
  location                  = "francecentral"
  azd_service_name          = "processor"
  storage_account_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stfunctest"
  storage_account_name      = "stfunctest"
  storage_blob_endpoint     = "https://stfunctest.blob.core.windows.net/"
  deployment_container_name = "app-package-func-test"
  runtime_name              = "python"
  runtime_version           = "3.12"
  app_settings              = { QUEUE_NAME = "audio" }
}

run "identity_based_storage_and_deployment" {
  command = plan

  assert {
    condition     = azapi_resource.plan.body.sku.name == "FC1" && azapi_resource.plan.body.properties.reserved
    error_message = "A Linux Flex Consumption plan."
  }
  assert {
    condition     = azapi_resource.app.body.properties.functionAppConfig.deployment.storage.authentication.type == "UserAssignedIdentity"
    error_message = "The deployment package is read with the app's identity."
  }
  assert {
    condition     = azapi_resource.app.body.properties.functionAppConfig.deployment.storage.value == "https://stfunctest.blob.core.windows.net/app-package-func-test"
    error_message = "The package lives in the app's own container."
  }
  assert {
    condition     = contains([for setting in azapi_resource.app.body.properties.siteConfig.appSettings : setting.name], "AzureWebJobsStorage__accountName")
    error_message = "Host storage goes through the identity."
  }
  assert {
    condition     = length(setintersection(["AzureWebJobsStorage", "FUNCTIONS_WORKER_RUNTIME", "WEBSITE_RUN_FROM_PACKAGE"], [for setting in azapi_resource.app.body.properties.siteConfig.appSettings : setting.name])) == 0
    error_message = "No storage connection string and no setting Flex Consumption deprecates."
  }
  assert {
    condition     = toset(keys(azurerm_role_assignment.host_storage)) == toset(["Storage Blob Data Owner", "Storage Queue Data Contributor", "Storage Table Data Contributor"])
    error_message = "The host's storage roles."
  }
  assert {
    condition     = azapi_resource.app.tags["azd-service-name"] == "processor"
    error_message = "azd finds the app through its service tag."
  }
}

run "entra_authenticated_telemetry" {
  command = plan

  variables {
    application_insights_connection_string = "InstrumentationKey=00000000-0000-0000-0000-000000000002"
  }

  assert {
    condition     = anytrue([for setting in nonsensitive(azapi_resource.app.body.properties.siteConfig.appSettings) : setting.name == "APPLICATIONINSIGHTS_AUTHENTICATION_STRING" && endswith(setting.value, ";Authorization=AAD")])
    error_message = "Telemetry is sent with the app's Entra identity."
  }
}

run "instance_memory_is_one_of_the_plans_sizes" {
  command = plan

  variables {
    instance_memory_mb = 1024
  }

  expect_failures = [var.instance_memory_mb]
}

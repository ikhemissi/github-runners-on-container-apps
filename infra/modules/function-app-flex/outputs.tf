output "id" {
  value = azapi_resource.app.id
}

output "name" {
  value = azapi_resource.app.name
}

output "url" {
  value = "https://${azapi_resource.app.output.properties.defaultHostName}"
}

output "identity_principal_id" {
  value = azurerm_user_assigned_identity.app.principal_id
}

output "identity_client_id" {
  value = azurerm_user_assigned_identity.app.client_id
}

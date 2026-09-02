output "resource_group_name" {
  description = "Resource group que contiene el storage account del tfstate."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account a usar en el backend azurerm de infra/live."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container a usar en el backend azurerm de infra/live."
  value       = azurerm_storage_container.tfstate.name
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

# output "container_registry_login_server" {
#   description = "Login server del ACR, para usar en `docker push` y en el pipeline de CI/CD."
#   value       = azurerm_container_registry.main.login_server
# }

output "function_app_url" {
  description = "URL pública de la Function App."
  value       = "https://${azurerm_function_app_flex_consumption.main.default_hostname}"
}

output "function_app_name" {
  description = "Nombre de la Function App, para usar en el pipeline de CI/CD (func azure functionapp publish)."
  value       = azurerm_function_app_flex_consumption.main.name
}

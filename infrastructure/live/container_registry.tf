# Deshabilitado temporalmente: el ACR Basic tiene costo fijo diario (~$5/mes)
# incluso sin uso. Se deja comentado hasta tener un pipeline de CI/CD real
# que publique imágenes propias. Mientras tanto, container_apps.tf usa la
# imagen pública `placeholder_image` sin necesidad de registry.
#
# resource "azurerm_container_registry" "main" {
#   name                = local.acr_name
#   resource_group_name = azurerm_resource_group.main.name
#   location            = azurerm_resource_group.main.location
#
#   sku           = "Basic"
#   admin_enabled = false # el Container App usa managed identity, no credenciales de admin
#
#   tags = local.common_tags
# }

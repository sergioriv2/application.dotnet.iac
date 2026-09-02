# Deshabilitado junto con container_registry.tf (ver ese archivo). Requiere
# azurerm_container_registry.main y el bloque `identity` del Container App.
#
# resource "azurerm_role_assignment" "acr_pull" {
#   scope                = azurerm_container_registry.main.id
#   role_definition_name = "AcrPull"
#   principal_id          = azurerm_container_app.main.identity[0].principal_id
# }

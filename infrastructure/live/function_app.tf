# Sufijo aleatorio para garantizar un nombre de Storage Account globalmente único
# (requerido por el Function App, aparte del Storage del tfstate en infra/bootstrap).
resource "random_id" "function_storage_suffix" {
  byte_length = 3
}

resource "azurerm_storage_account" "function_app" {
  name                = "st${local.name_prefix_alnum}fn${random_id.function_storage_suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.common_tags
}

# Contenedor donde Flex Consumption guarda el paquete de despliegue de la función.
resource "azurerm_storage_container" "deployments" {
  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.function_app.id
  container_access_type = "private"
}

resource "azurerm_service_plan" "main" {
  name                = "asp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "FC1" # Flex Consumption: sucesor de Y1, capa gratuita mensual similar

  tags = local.common_tags
}

resource "azurerm_function_app_flex_consumption" "main" {
  name                = "func-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.function_app.primary_blob_endpoint}${azurerm_storage_container.deployments.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.function_app.primary_access_key

  runtime_name           = "dotnet-isolated"
  runtime_version         = "10.0"
  maximum_instance_count  = 100
  instance_memory_in_mb   = 2048

  site_config {}

  tags = local.common_tags
}

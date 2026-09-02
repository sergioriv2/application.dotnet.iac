# Backend remoto: los valores de storage_account_name y container_name salen
# de los outputs de `infra/bootstrap` (terraform output -raw storage_account_name).
# Reemplaza los placeholders abajo (o pásalos con -backend-config en `terraform init`)
# después de aplicar infra/bootstrap.
#
# Para un entorno que no sea "dev", pasá una key de state distinta con
# -backend-config, ej: terraform init -backend-config="key=iactest.qa.tfstate"
# (el atributo `key` de un bloque backend no admite interpolación de variables).
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-iactest-tfstate"
    storage_account_name = "stiactesttfstate286712"
    container_name       = "tfstate"
    key                  = "iactest.dev.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

variable "project" {
  description = "Nombre corto del proyecto, usado como prefijo en los nombres de recursos."
  type        = string
  default     = "iactest"
}

variable "environment" {
  description = "Entorno lógico (dev, qa, prod)."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Región de Azure donde se crean todos los recursos."
  type        = string
  default     = "eastus2"
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Los nombres de ACR y Storage no admiten guiones; el resto de recursos sí.
  acr_name          = replace("${var.project}${var.environment}acr", "-", "")
  name_prefix_alnum = replace(local.name_prefix, "-", "")

  common_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Requerido por azurerm_container_app_environment para logs y métricas.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

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
  runtime_version        = "10.0"
  maximum_instance_count = 100
  instance_memory_in_mb  = 2048

  site_config {}

  tags = local.common_tags
}

# --- ACR + RBAC: deshabilitados intencionalmente ---
# El ACR Basic tiene costo fijo diario (~$5/mes) incluso sin uso. Se dejan
# comentados hasta tener un pipeline de CI/CD real que publique imágenes
# propias. Mientras tanto, la Function App no requiere registry.
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
#
# resource "azurerm_role_assignment" "acr_pull" {
#   scope                = azurerm_container_registry.main.id
#   role_definition_name = "AcrPull"
#   principal_id          = azurerm_container_app.main.identity[0].principal_id
# }

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

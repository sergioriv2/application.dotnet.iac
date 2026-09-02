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
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.project}-tfstate"
  location = var.location

  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "tfstate"
  }
}

# Sufijo aleatorio para garantizar un nombre de Storage Account globalmente único
# (las cuentas de storage comparten namespace en todo Azure).
resource "random_id" "tfstate_suffix" {
  byte_length = 3
}

resource "azurerm_storage_account" "tfstate" {
  name                = "st${var.project}tfstate${random_id.tfstate_suffix.hex}"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "tfstate"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

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

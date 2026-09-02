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

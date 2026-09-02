# Backend remoto: los valores de storage_account_name y container_name salen
# de los outputs de `infra/bootstrap` (terraform output -raw storage_account_name).
# Reemplaza los placeholders abajo (o pásalos con -backend-config en `terraform init`)
# después de aplicar infra/bootstrap.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-iactest-tfstate"
    storage_account_name = "stiactesttfstate286712"
    container_name        = "tfstate"
    key                    = "iactest.dev.tfstate"
    use_azuread_auth       = true
  }
}

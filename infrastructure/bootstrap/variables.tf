variable "project" {
  description = "Nombre corto del proyecto, usado como prefijo en los nombres de recursos."
  type        = string
  default     = "iactest"
}

variable "environment" {
  description = "Entorno lógico (dev, staging, prod). Por ahora solo se usa 'dev'."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Región de Azure donde se crea el Storage Account del tfstate."
  type        = string
  default     = "eastus2"
}

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
  description = "Región de Azure donde se crean todos los recursos."
  type        = string
  default     = "eastus2"
}

# container_port / placeholder_image ya no aplican: la app pasó de Web API en
# Container App a Azure Function (ver function_app.tf). Se dejan fuera hasta
# que el Container App se reactive (ver container_apps.tf en el historial de git).

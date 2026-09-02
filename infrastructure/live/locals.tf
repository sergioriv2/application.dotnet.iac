locals {
  name_prefix = "${var.project}-${var.environment}"

  # Los nombres de ACR y Storage no admiten guiones; el resto de recursos sí.
  acr_name           = replace("${var.project}${var.environment}acr", "-", "")
  name_prefix_alnum  = replace(local.name_prefix, "-", "")

  common_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

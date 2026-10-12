terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    oci      = { source = "oracle/oci", version = "9.9.0" }
    external = { source = "hashicorp/external", version = "2.3.5" }
  }
}
provider "oci" {
  region              = var.region
  auth                = var.auth
  config_file_profile = contains(["APIKey", "SecurityToken"], var.auth) ? var.config_file_profile : null
}

# IAM writes use the tenancy home region, which may differ from the OKE region.
provider "oci" {
  alias               = "home"
  region              = var.iam_home_region == "" ? var.region : var.iam_home_region
  auth                = var.auth
  config_file_profile = contains(["APIKey", "SecurityToken"], var.auth) ? var.config_file_profile : null
}

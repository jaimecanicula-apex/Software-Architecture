# One-time bootstrap: the storage account that holds Terraform remote state.
# Run once per subscription (or once for a central state subscription) with local state:
#   terraform -chdir=infra/bootstrap init
#   terraform -chdir=infra/bootstrap apply -var-file=<file>.tfvars
# Then copy the outputs into environments/<env>/backend.hcl.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  storage_use_azuread = true

  features {}
}

variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type    = string
  default = null
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "resource_group_name" {
  description = "e.g. rg-tfstate-prod"
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique, 3-24 lowercase letters and digits (e.g. sttfstateprod001)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "state_writer_principal_ids" {
  description = "Object IDs of the pipeline identities (and admins) that run Terraform."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # Entra ID auth only
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "state" {
  name       = "lock-tfstate"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state."
}

resource "azurerm_role_assignment" "state_writer" {
  for_each = toset(var.state_writer_principal_ids)

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

output "backend_config" {
  description = "Paste into environments/<env>/backend.hcl (set key per environment)."
  value       = <<-HCL
    subscription_id      = "${var.subscription_id}"
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    key                  = "static-website/<env>.tfstate"
    use_azuread_auth     = true
  HCL
}

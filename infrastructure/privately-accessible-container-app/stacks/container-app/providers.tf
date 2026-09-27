provider "azurerm" {
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Creates the app registration used for sign-in.
provider "azuread" {
  tenant_id = var.tenant_id
}

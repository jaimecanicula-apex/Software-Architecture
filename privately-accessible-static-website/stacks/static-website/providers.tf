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

# Creates the app registration used for APEX sign-in.
provider "azuread" {
  tenant_id = var.tenant_id
}

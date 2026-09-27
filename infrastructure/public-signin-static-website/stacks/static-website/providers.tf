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

# App registration, users group and B2B invitations in the APEX tenant.
provider "azuread" {
  tenant_id = var.tenant_id
}

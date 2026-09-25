# Azure Static Web App hosting the build-free site in app/.
# Content is deployed by the GitHub Actions or Azure Pipelines delivery option, not by Terraform.

resource "azurerm_static_web_app" "this" {
  name                               = var.name
  resource_group_name                = var.resource_group_name
  location                           = var.location
  sku_tier                           = var.sku
  sku_size                           = var.sku
  preview_environments_enabled       = var.preview_environments_enabled
  configuration_file_changes_enabled = true
  public_network_access_enabled      = var.public_network_access_enabled
  app_settings                       = var.app_settings
  tags                               = var.tags
}

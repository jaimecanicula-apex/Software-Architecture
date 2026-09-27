# Azure Monitor Private Link Scope: telemetry from inside the VNet (the
# availability probe) reaches Log Analytics and Application Insights over a
# private endpoint instead of the internet.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "linked_resource_ids" {
  description = "Log Analytics workspace and Application Insights IDs, keyed by a short name."
  type        = map(string)
}

variable "private_dns_zone_ids" {
  description = "IDs of the Azure Monitor private DNS zones."
  type        = list(string)
}

variable "query_access_mode" {
  description = "Open lets viewers query from the Azure portal over the internet; PrivateOnly requires them to be on the APEX network."
  type        = string
  default     = "Open"
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_monitor_private_link_scope" "this" {
  name                  = var.name
  resource_group_name   = var.resource_group_name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = var.query_access_mode
  tags                  = var.tags
}

resource "azurerm_monitor_private_link_scoped_service" "this" {
  for_each = var.linked_resource_ids

  name                = "ampls-${each.key}"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = each.value
}

module "endpoint" {
  source = "../private-endpoint"

  name                 = "pe-${var.name}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  subnet_id            = var.subnet_id
  target_resource_id   = azurerm_monitor_private_link_scope.this.id
  subresource_names    = ["azuremonitor"]
  private_dns_zone_ids = var.private_dns_zone_ids
  tags                 = var.tags

  depends_on = [azurerm_monitor_private_link_scoped_service.this]
}

output "id" {
  value = azurerm_monitor_private_link_scope.this.id
}

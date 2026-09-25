# One private endpoint with its DNS zone group, so the service resolves to a
# private IP inside the VNet (and any linked hub).

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

variable "target_resource_id" {
  type = string
}

variable "subresource_names" {
  description = "e.g. [\"staticSites\"] or [\"azuremonitor\"]."
  type        = list(string)
}

variable "private_dns_zone_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_private_endpoint" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.subnet_id
  custom_network_interface_name = "nic-${var.name}"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = var.subresource_names
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = var.private_dns_zone_ids
  }
}

output "id" {
  value = azurerm_private_endpoint.this.id
}

output "private_ip_address" {
  value = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

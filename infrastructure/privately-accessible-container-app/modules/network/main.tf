# Spoke network: one VNet with the subnet the Container Apps environment runs in,
# an NSG that refuses anything from the internet, and optional hub peering so
# users on the corporate network can reach the app.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  description = "VNet name, e.g. vnet-pca-dev-weu-001."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "Must not overlap the hub or other spokes; take it from the IP plan."
  type        = list(string)
}

variable "container_apps_subnet_name" {
  description = "From the naming module, e.g. snet-cae-pca-dev-weu-001."
  type        = string
}

variable "nsg_name" {
  type = string
}

variable "container_apps_subnet_prefix" {
  description = "At least /27. Delegated to Microsoft.App/environments."
  type        = string
}

variable "dns_servers" {
  description = "Custom DNS servers (e.g. the hub DNS resolver). Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "hub_virtual_network_id" {
  description = "Optional hub VNet: creates the spoke-side peering. The hub side is owned by the platform team."
  type        = string
  default     = null
}

variable "use_hub_gateway" {
  description = "Route through the hub's VPN/ExpressRoute gateway (the hub side must allow gateway transit)."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = var.container_apps_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.container_apps_subnet_prefix]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_network_security_group" "container_apps" {
  name                = var.nsg_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "AllowHttpsFromVirtualNetwork"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = azurerm_subnet.container_apps.id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}

resource "azurerm_virtual_network_peering" "to_hub" {
  count = var.hub_virtual_network_id == null ? 0 : 1

  name                         = "peer-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.hub_virtual_network_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = var.use_hub_gateway
}

output "virtual_network_id" {
  value = azurerm_virtual_network.this.id
}

output "container_apps_subnet_id" {
  value = azurerm_subnet.container_apps.id
}

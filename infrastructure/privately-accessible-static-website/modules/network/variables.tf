variable "name" {
  description = "VNet name, e.g. vnet-sws-dev-weu-001."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "Must not overlap the APEX hub or other spokes; take it from the IP plan."
  type        = list(string)
}

variable "subnet_names" {
  description = "From the naming module."
  type = object({
    private_endpoints = string
    probe             = string
  })
}

variable "nsg_names" {
  type = object({
    private_endpoints = string
    probe             = string
  })
}

variable "private_endpoint_subnet_prefix" {
  type = string
}

variable "probe_subnet_prefix" {
  description = "At least /27, delegated to Container Apps."
  type        = string
}

variable "dns_servers" {
  description = "Custom DNS servers (e.g. the hub DNS resolver). Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "private_dns_zones" {
  description = "Private DNS zones to create and link to this VNet."
  type        = list(string)
  default     = []
}

variable "hub_virtual_network_id" {
  description = "Optional APEX hub VNet: creates the spoke-side peering and links every zone to the hub."
  type        = string
  default     = null
}

variable "use_hub_gateway" {
  description = "Route through the hub's VPN/ExpressRoute gateway (requires the hub side to allow gateway transit)."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Azure Database for PostgreSQL Flexible Server, VNet-integrated: reachable
# only from its delegated subnet, never from the public internet.

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

variable "delegated_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "postgresql_version" {
  type    = string
  default = "16"
}

variable "sku_name" {
  description = "e.g. B_Standard_B1ms (Burstable, dev/qa) or GP_Standard_D2ds_v5 (General Purpose, uat/prod)."
  type        = string
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "backup_retention_days" {
  type    = number
  default = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "ha_enabled" {
  description = "Zone-redundant or same-zone standby. Needs a non-Burstable sku_name. Fixed at creation."
  type        = bool
  default     = false
}

variable "ha_mode" {
  type    = string
  default = "ZoneRedundant"

  validation {
    condition     = contains(["ZoneRedundant", "SameZone"], var.ha_mode)
    error_message = "ha_mode must be ZoneRedundant or SameZone."
  }
}

variable "zone" {
  description = "Primary availability zone, e.g. \"1\". Null lets Azure pick."
  type        = string
  default     = null
}

variable "standby_zone" {
  description = "Standby zone when ha_mode = ZoneRedundant. Ignored otherwise."
  type        = string
  default     = null
}

variable "administrator_login" {
  type = string
}

variable "administrator_password" {
  type      = string
  sensitive = true
}

variable "database_name" {
  type    = string
  default = "app"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# A Burstable server has no standby to fail over to. Enforced by the caller
# (the stack's own "postgresql_ha_needs_non_burstable_sku" check), not here:
# a terraform test's expect_failures can only target a checkable object in
# the configuration under test, never one inside a child module, so keeping
# the same rule in both places would make one of them untestable and the
# two could drift out of sync.

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgresql_version

  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  zone       = var.zone

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  dynamic "high_availability" {
    for_each = var.ha_enabled ? [1] : []
    content {
      mode                      = var.ha_mode
      standby_availability_zone = var.ha_mode == "ZoneRedundant" ? var.standby_zone : null
    }
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

output "server_id" {
  value = azurerm_postgresql_flexible_server.this.id
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.app.name
}

# Target

variable "subscription_id" {
  description = "Subscription that hosts this environment. Each environment can use a different one."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "tenant_id" {
  description = "Entra ID tenant. Sign-in is restricted to this tenant."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "environment must be dev, qa, uat or prod."
  }
}

variable "location" {
  description = "Region for every regional resource, e.g. westeurope. No default: set it per environment."
  type        = string
}

variable "workload" {
  description = "Short workload code used in resource names."
  type        = string
  default     = "pcds"
}

variable "instance" {
  type    = string
  default = "001"
}

variable "application_name" {
  type    = string
  default = "Private container app"
}

# Governance

variable "governance_tags" {
  description = "Mandatory tags applied to every resource."
  type = object({
    owner               = string
    cost_centre         = string
    data_classification = string
    support             = string
  })
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

variable "enable_delete_lock" {
  type    = bool
  default = false
}

variable "monthly_budget" {
  description = "Monthly cost budget for the resource group. 0 disables it."
  type        = number
  default     = 0
}

variable "budget_start_date" {
  description = "First day of a month, e.g. 2026-10-01T00:00:00Z."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

# Network

variable "vnet_address_space" {
  description = "Must not overlap the hub or other spokes; take it from the IP plan."
  type        = list(string)
}

variable "container_apps_subnet_prefix" {
  description = "At least /27, inside vnet_address_space."
  type        = string
}

variable "dns_servers" {
  description = "Custom DNS servers for the spoke (e.g. the hub DNS resolver). Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "hub_virtual_network_id" {
  description = "Hub VNet that corporate users reach Azure through. Null leaves the spoke unpeered (reachable only from inside it)."
  type        = string
  default     = null
}

variable "use_hub_gateway" {
  type    = bool
  default = false
}

# Sign-in

variable "allowed_group_ids" {
  description = "Entra group object IDs allowed to sign in. Only members of these groups can open the app."
  type        = list(string)
}

variable "entra_app_owners" {
  description = "Object IDs that own the app registration (the deploying identity is always added)."
  type        = list(string)
  default     = []
}

# Application

variable "create_container_app" {
  description = "False on the very first apply, while the registry is still empty. Set true once the first image is pushed."
  type        = bool
  default     = false
}

variable "image_repository" {
  type    = string
  default = "python-crud-app"
}

variable "initial_image_tag" {
  type    = string
  default = "initial"
}

variable "zone_redundancy_enabled" {
  description = "Spread the Container Apps environment and its replicas across availability zones. Needs a region with zones, and min_replicas >= 2 to be useful. Fixed at creation: changing it recreates the environment."
  type        = bool
  default     = false
}

variable "registry_sku" {
  description = "Basic, Standard or Premium. Premium adds private endpoints, geo-replication and zone redundancy."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.registry_sku)
    error_message = "registry_sku must be Basic, Standard or Premium."
  }
}

variable "registry_zone_redundancy_enabled" {
  description = "Keep registry copies in every availability zone of the region. Premium only; fixed at creation."
  type        = bool
  default     = false

  validation {
    condition     = !var.registry_zone_redundancy_enabled || var.registry_sku == "Premium"
    error_message = "registry_zone_redundancy_enabled needs registry_sku = Premium."
  }
}

variable "container_cpu" {
  type    = number
  default = 1
}

variable "container_memory" {
  type    = string
  default = "2Gi"
}

variable "min_replicas" {
  description = "1 keeps the app warm. 0 saves cost but the first request after idle waits for a cold start."
  type        = number
  default     = 1
}

variable "max_replicas" {
  type    = number
  default = 1
}

variable "app_settings" {
  description = "Plain environment variables for the app, e.g. APP_MAX_UPLOAD_MB."
  type        = map(string)
  default     = {}
}

# Monitoring

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_daily_quota_gb" {
  type    = number
  default = -1
}

variable "alert_email_receivers" {
  type    = list(string)
  default = []
}

variable "monitoring_viewer_principal_ids" {
  description = "Entra group object IDs that can read logs, metrics and alerts for this environment."
  type        = list(string)
  default     = []
}

# Network: two more subnets beyond the container apps one.

variable "postgresql_subnet_prefix" {
  description = "At least /28, inside vnet_address_space, not overlapping the other subnets."
  type        = string
}

variable "private_endpoints_subnet_prefix" {
  description = "At least /28, inside vnet_address_space, not overlapping the other subnets."
  type        = string
}

# privatelink.* zone names are fixed by Azure, unlike the Container Apps
# environment domain, so every environment linking its own copy to a shared
# hub collides (a VNet cannot link to two zones with the same name). Leave
# these null and each environment creates its own zone linked only to its
# own spoke (safe by default, no hub link, no cross-environment collision).
# Set one to a platform-team-managed central zone's ID to reuse it instead,
# including from the hub.
variable "postgresql_private_dns_zone_id" {
  type    = string
  default = null
}

variable "key_vault_private_dns_zone_id" {
  type    = string
  default = null
}

variable "storage_private_dns_zone_id" {
  type    = string
  default = null
}

# Database

variable "postgresql_version" {
  type    = string
  default = "16"
}

variable "postgresql_sku_name" {
  description = "e.g. B_Standard_B1ms (Burstable, dev/qa) or GP_Standard_D2ds_v5 (General Purpose, uat/prod)."
  type        = string
}

variable "postgresql_storage_mb" {
  type    = number
  default = 32768
}

variable "postgresql_backup_retention_days" {
  type    = number
  default = 7
}

variable "postgresql_geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "postgresql_ha_enabled" {
  description = "Zone-redundant or same-zone standby. Needs a non-Burstable postgresql_sku_name. Fixed at creation."
  type        = bool
  default     = false
}

variable "postgresql_ha_mode" {
  type    = string
  default = "ZoneRedundant"
}

variable "postgresql_zone" {
  description = "Primary availability zone, e.g. \"1\". Null lets Azure pick."
  type        = string
  default     = null
}

variable "postgresql_standby_zone" {
  description = "Standby zone when postgresql_ha_mode = ZoneRedundant."
  type        = string
  default     = null
}

variable "postgresql_administrator_login" {
  type    = string
  default = "appadmin"
}

# Storage (images)

variable "storage_replication_type" {
  description = "LRS, ZRS, GZRS or RAGZRS. ZRS in dev/qa, GZRS in uat/prod."
  type        = string
  default     = "ZRS"
}

variable "storage_soft_delete_retention_days" {
  type    = number
  default = 7
}

# Key Vault

variable "key_vault_purge_protection_enabled" {
  type    = bool
  default = false
}

variable "key_vault_allowed_ip_ranges" {
  description = "Public IP ranges (CIDR) allowed to reach the vault's data plane during terraform apply. Empty means Terraform must run from inside the spoke's network."
  type        = list(string)
  default     = []
}

# Seed users

variable "seed_admin_username" {
  type    = string
  default = "admin"
}

variable "seed_demo_username" {
  type    = string
  default = "demo"
}

# Monitoring thresholds

variable "postgresql_cpu_alert_threshold" {
  type    = number
  default = 80
}

variable "storage_used_capacity_alert_threshold_gb" {
  type    = number
  default = 50
}

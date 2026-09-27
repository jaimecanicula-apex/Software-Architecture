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
  description = "The APEX Entra ID tenant. Sign-in is restricted to this tenant."
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
  description = "Region for everything. Static Web Apps is only offered in westus2, centralus, eastus2, westeurope and eastasia."
  type        = string
}

variable "workload" {
  description = "Short workload code used in resource names."
  type        = string
  default     = "swi"
}

variable "instance" {
  type    = string
  default = "001"
}

variable "application_name" {
  type    = string
  default = "Internal Static Website"
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
  type    = string
  default = "2026-10-01T00:00:00Z"
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

# Hosting

variable "preview_environments_enabled" {
  description = "Pull-request previews. They are private too, reachable only from the APEX network."
  type        = bool
  default     = true
}

# Network (this design creates its own spoke VNet)

variable "vnet_address_space" {
  description = "Take it from the APEX IP plan; must not overlap the hub or other spokes."
  type        = list(string)
}

variable "private_endpoint_subnet_prefix" {
  type = string
}

variable "probe_subnet_prefix" {
  description = "At least /27, delegated to Container Apps."
  type        = string
}

variable "dns_servers" {
  description = "Custom DNS servers for the VNet (e.g. the hub DNS resolver). Empty uses Azure DNS."
  type        = list(string)
  default     = []
}

variable "hub_virtual_network_id" {
  description = "Optional APEX hub VNet: spoke-side peering plus Private DNS zone links, so users on the corporate network resolve and reach the site."
  type        = string
  default     = null
}

variable "use_hub_gateway" {
  type    = bool
  default = false
}

# Sign-in (APEX Entra only)

variable "create_entra_app" {
  description = "true: Terraform creates the app registration. false: supply an existing one below (for tenants where pipelines may not create app registrations)."
  type        = bool
  default     = true
}

variable "allowed_group_ids" {
  description = "Entra group object IDs allowed to sign in. Everyone else in APEX is refused."
  type        = list(string)
  default     = []
}

variable "entra_app_owners" {
  type    = list(string)
  default = []
}

variable "existing_entra_client_id" {
  type    = string
  default = null
}

variable "existing_entra_client_secret" {
  type      = string
  default   = null
  sensitive = true
}

# Monitoring

variable "enable_monitoring" {
  description = "One switch for all monitoring: logs, availability checks, alerts, dashboard and monitoring access. Can be off in dev to save cost; always on in prod."
  type        = bool
  default     = true

  validation {
    condition     = var.enable_monitoring || var.environment != "prod"
    error_message = "Monitoring cannot be turned off in prod."
  }
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "log_daily_quota_gb" {
  type    = number
  default = -1
}

variable "monitoring_query_from_internet" {
  description = "true lets viewers open the dashboard and query logs from the Azure portal anywhere they can sign in; false requires the APEX network. Telemetry ingestion is always private."
  type        = bool
  default     = true
}

variable "probe_zone_redundancy_enabled" {
  description = "Spread the availability probe's Container Apps environment across availability zones, so a zone failure does not silence the probe and raise a false alert. Fixed at creation. The Static Web App, private endpoints and Private DNS are zone-resilient by the platform and have no setting."
  type        = bool
  default     = false
}

variable "probe_cron" {
  type    = string
  default = "*/5 * * * *"
}

variable "probe_image" {
  description = "Image for the in-network probe. Mirror it into an APEX registry for a fully private pull."
  type        = string
  default     = "mcr.microsoft.com/azure-cli:latest"
}

variable "alert_email_receivers" {
  type    = list(string)
  default = []
}

variable "alert_webhook_receivers" {
  type      = map(string)
  default   = {}
  sensitive = true
}

variable "alert_thresholds" {
  type = object({
    availability_percent = optional(number)
  })
  default = {}
}

variable "enable_service_health_alert" {
  description = "Azure incident alert for the whole subscription. When environments share a subscription, keep it true in only one of them to avoid duplicate alerts."
  type        = bool
  default     = true
}

variable "export_activity_log" {
  type    = bool
  default = false
}

variable "monitoring_viewer_principal_ids" {
  description = "Entra ID object IDs (groups preferred) allowed to view dashboards, logs and alerts."
  type        = list(string)
  default     = []
}

variable "monitoring_operator_principal_ids" {
  type    = list(string)
  default = []
}

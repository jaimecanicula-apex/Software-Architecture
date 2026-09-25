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
  description = "Entra ID tenant. Null uses the tenant of the signed-in identity."
  type        = string
  default     = null
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "environment must be dev, qa, uat or prod."
  }
}

variable "location" {
  description = "Region for the resource group, Static Web App and monitoring. Front Door is global."
  type        = string
  default     = "westeurope"
}

variable "workload" {
  description = "Short workload code used in resource names."
  type        = string
  default     = "sws"
}

variable "instance" {
  type    = string
  default = "001"
}

variable "application_name" {
  description = "Human-readable application name, used in tags."
  type        = string
  default     = "Static Website"
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
  description = "CanNotDelete lock on the resource group (recommended for uat and prod)."
  type        = bool
  default     = false
}

variable "monthly_budget" {
  description = "Monthly cost budget for the resource group in the billing currency. 0 disables it."
  type        = number
  default     = 0
}

variable "budget_start_date" {
  description = "First day of the budget period, RFC3339 (e.g. 2026-10-01T00:00:00Z)."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

# Hosting

variable "static_web_app_sku" {
  description = "Free or Standard. Standard is required to lock the origin to Front Door."
  type        = string
  default     = "Standard"
}

variable "preview_environments_enabled" {
  type    = bool
  default = true
}

# Edge

variable "enable_front_door" {
  description = "Put Azure Front Door and its WAF in front of the site. Can be off in dev to save cost."
  type        = bool
  default     = true
}

variable "front_door_sku" {
  description = "Standard_AzureFrontDoor or Premium_AzureFrontDoor (Premium adds WAF managed rule sets)."
  type        = string
  default     = "Standard_AzureFrontDoor"
}

variable "custom_domains" {
  description = "Custom domains on Front Door. monitor = false skips the availability test until DNS is cut over."
  type = map(object({
    host_name   = string
    dns_zone_id = optional(string)
    monitor     = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = length(var.custom_domains) == 0 || var.enable_front_door
    error_message = "custom_domains require enable_front_door = true."
  }
}

variable "waf_mode" {
  type    = string
  default = "Prevention"
}

variable "waf_rate_limit_per_minute" {
  type    = number
  default = 1000
}

variable "waf_blocked_country_codes" {
  type    = list(string)
  default = []
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

variable "availability_test_locations" {
  description = "Null keeps the module default (five regions across Europe, US and Asia)."
  type        = list(string)
  default     = null
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
    availability_percent  = optional(number)
    origin_health_percent = optional(number)
    error_5xx_percent     = optional(number)
    error_4xx_percent     = optional(number)
    latency_ms            = optional(number)
    waf_blocks_per_15min  = optional(number)
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
  description = "Entra ID object IDs allowed to manage alerts and dashboards."
  type        = list(string)
  default     = []
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "name_suffix" {
  description = "Suffix used for alert, web test and workbook names (e.g. sws-prod-weu-001)."
  type        = string
}

variable "log_analytics_name" {
  type = string
}

variable "application_insights_name" {
  type = string
}

variable "action_group_name" {
  type = string
}

variable "action_group_short_name" {
  description = "Up to 12 characters; appears in SMS and email notifications."
  type        = string

  validation {
    condition     = length(var.action_group_short_name) <= 12
    error_message = "action_group_short_name must be 12 characters or fewer."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention (30-730 days)."
  type        = number
  default     = 90
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB; -1 for no cap."
  type        = number
  default     = -1
}

# What to monitor

variable "front_door_enabled" {
  description = "Front Door exists in this environment (known at plan time, unlike its ID)."
  type        = bool
}

variable "front_door_profile_id" {
  type    = string
  default = null
}

variable "availability_tests" {
  description = "Public URLs to test from several internet regions, keyed by a short, plan-time-known name. Empty for private sites."
  type        = map(string)
  default     = {}
}

variable "custom_availability_test_names" {
  description = "Availability results sent by an in-network probe (private sites). Each gets an availability alert and a silence alert."
  type        = list(string)
  default     = []
}

variable "internet_ingestion_enabled" {
  description = "false: telemetry only arrives through the Azure Monitor Private Link Scope."
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "false: viewers must be on the APEX network to query logs and open the dashboard."
  type        = bool
  default     = true
}

variable "availability_test_locations" {
  description = "Availability test locations (Application Insights location IDs)."
  type        = list(string)
  default = [
    "emea-nl-ams-azr",  # West Europe
    "emea-gb-db3-azr",  # North Europe
    "emea-ru-msa-edge", # UK South
    "us-va-ash-azr",    # East US
    "apac-sg-sin-azr",  # Southeast Asia
  ]
}

variable "availability_test_frequency_seconds" {
  type    = number
  default = 300
}

variable "certificate_expiry_warning_days" {
  description = "Availability tests fail when the TLS certificate expires within this many days."
  type        = number
  default     = 14
}

# Alerting

variable "alert_email_receivers" {
  description = "Email addresses notified by the Action Group."
  type        = list(string)
  default     = []
}

variable "alert_webhook_receivers" {
  description = "Webhooks (Teams, ITSM, PagerDuty...) keyed by name."
  type        = map(string)
  default     = {}
}

variable "alert_thresholds" {
  type = object({
    availability_percent  = optional(number, 90)
    origin_health_percent = optional(number, 90)
    error_5xx_percent     = optional(number, 5)
    error_4xx_percent     = optional(number, 25)
    latency_ms            = optional(number, 2000)
    waf_blocks_per_15min  = optional(number, 100)
  })
  default = {}
}

variable "service_health_alert_enabled" {
  description = "Alert on Azure incidents affecting the subscription. Enable it in only one environment per subscription."
  type        = bool
  default     = true
}

variable "export_activity_log" {
  description = "Send the subscription Activity Log to this workspace. Leave false if the subscription already exports it elsewhere (one setting per destination)."
  type        = bool
  default     = false
}

# Who can see it

variable "viewer_principal_ids" {
  description = "Entra ID object IDs (groups preferred) who can view the dashboard, logs, metrics and alerts."
  type        = list(string)
  default     = []
}

variable "operator_principal_ids" {
  description = "Entra ID object IDs who can also manage alerts, action groups and the workbook."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

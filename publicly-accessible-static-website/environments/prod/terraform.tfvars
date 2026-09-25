# PROD environment. Replace every placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000004" # <prod subscription id>
# tenant_id     = "<tenant id>"   # only if the subscription is in another tenant

environment = "prod"
location    = "westeurope"
workload    = "sws"
instance    = "001"

governance_tags = {
  owner               = "<owner team>"
  cost_centre         = "<cost centre>"
  data_classification = "Public"
  support             = "<support group or email>"
}

extra_tags = {}

enable_delete_lock = true
monthly_budget     = 500
budget_start_date  = "2026-10-01T00:00:00Z"
budget_contact_emails = [
  # "finance@example.com",
]

# Hosting
static_web_app_sku           = "Standard"
preview_environments_enabled = false

# Edge
enable_front_door = true
front_door_sku    = "Premium_AzureFrontDoor"
waf_mode          = "Prevention"
custom_domains = {
  apex = {
    host_name = "example.com"
    monitor   = false # set true once DNS points at Front Door
  }
  www = {
    host_name = "www.example.com"
    monitor   = false
  }
}

# Monitoring (one switch for all of it; cannot be false in prod)
enable_monitoring  = true
log_retention_days = 180
alert_email_receivers = [
  # "alerts@example.com",
]
alert_thresholds = {
  availability_percent = 95
  error_5xx_percent    = 2
  latency_ms           = 1500
}
export_activity_log         = false # true if this subscription does not already export its Activity Log
enable_service_health_alert = true  # false in all but one environment sharing a subscription

# People who can open the dashboard, query logs and see alerts
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: service owners>",
  # "<entra-group-object-id: support desk>",
  # "<entra-group-object-id: security operations>",
]

# People who can also change alerts and dashboards
monitoring_operator_principal_ids = [
  # "<entra-group-object-id: operations>",
]

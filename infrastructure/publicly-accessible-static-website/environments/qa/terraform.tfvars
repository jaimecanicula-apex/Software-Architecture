# QA environment. Replace every placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000002" # <qa subscription id>
# tenant_id     = "<tenant id>"   # only if the subscription is in another tenant

environment = "qa"
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

enable_delete_lock = false
monthly_budget     = 100
budget_start_date  = "2026-10-01T00:00:00Z"
budget_contact_emails = [
  # "finance@example.com",
]

# Hosting
static_web_app_sku           = "Standard"
preview_environments_enabled = true

# Edge
enable_front_door = true
front_door_sku    = "Standard_AzureFrontDoor"
waf_mode          = "Detection"
custom_domains    = {}

# Monitoring (one switch for all of it; cannot be false in prod)
enable_monitoring  = true
log_retention_days = 30
alert_email_receivers = [
  # "alerts@example.com",
]
alert_thresholds            = {}
export_activity_log         = false # true if this subscription does not already export its Activity Log
enable_service_health_alert = true  # false in all but one environment sharing a subscription

# People who can open the dashboard, query logs and see alerts
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: developers>",
  # "<entra-group-object-id: testers>",
]

# People who can also change alerts and dashboards
monitoring_operator_principal_ids = [
  # "<entra-group-object-id: operations>",
]

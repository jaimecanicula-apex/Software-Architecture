# UAT environment. Replace every placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000003" # <uat subscription id>
# tenant_id     = "<tenant id>"   # only if the subscription is in another tenant

environment = "uat"
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
monthly_budget     = 400
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
  www = {
    host_name = "uat.example.com"
    monitor   = false # set true once DNS points at Front Door
  }
}

# Monitoring
log_retention_days = 90
alert_email_receivers = [
  # "alerts@example.com",
]
alert_thresholds    = {}
export_activity_log = false # true if this subscription does not already export its Activity Log

# People who can open the dashboard, query logs and see alerts
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: project team>",
  # "<entra-group-object-id: business testers>",
]

# People who can also change alerts and dashboards
monitoring_operator_principal_ids = [
  # "<entra-group-object-id: operations>",
]

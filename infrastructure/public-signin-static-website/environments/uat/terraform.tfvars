# UAT: public sign-in static website (internet-facing, Entra ID sign-in, approved guests only).
# Replace every placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000023" # <uat subscription id>
tenant_id       = "00000000-0000-0000-0000-00000000000a" # <APEX tenant id>

environment = "uat"
location    = "westeurope"
workload    = "sps"
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

# Sign-in: external people are invited as B2B guests of the APEX tenant
guest_emails = [
  # "partner.contact@example.com",
]
allowed_group_ids = [
  # "<entra-group-object-id: existing approved partner group>",
]
create_entra_app = true

# Monitoring (one switch for all of it; cannot be false in prod)
enable_monitoring  = true
log_retention_days = 90
alert_email_receivers = [
  # "alerts@example.com",
]
alert_thresholds            = {}
export_activity_log         = false # true if this subscription does not already export its Activity Log
enable_service_health_alert = true  # false in all but one environment sharing a subscription

# People who can open the dashboard, query logs and see alerts
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: project team>",
  # "<entra-group-object-id: business testers>",
]

# People who can also change alerts and dashboards
monitoring_operator_principal_ids = [
  # "<entra-group-object-id: operations>",
]

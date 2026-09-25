# PROD: privately accessible static website (internal users only).
# Replace every placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000014" # <prod subscription id>
tenant_id       = "00000000-0000-0000-0000-00000000000a" # <APEX tenant id>

environment = "prod"
location    = "westeurope"
workload    = "swi"
instance    = "001"

governance_tags = {
  owner               = "<owner team>"
  cost_centre         = "<cost centre>"
  data_classification = "Internal"
  support             = "<support group or email>"
}

enable_delete_lock = true
monthly_budget     = 300
budget_start_date  = "2026-10-01T00:00:00Z"

preview_environments_enabled = false

# Network: take the ranges from the APEX IP plan (these are placeholders)
vnet_address_space             = ["10.240.3.0/24"]
private_endpoint_subnet_prefix = "10.240.3.0/27"
probe_subnet_prefix            = "10.240.3.32/27"
# dns_servers            = ["<hub DNS resolver IP>"]
# hub_virtual_network_id = "<APEX hub VNet resource id>"   # peering + DNS links so corporate users can reach the site

# Sign-in: only these APEX Entra groups can open the site
allowed_group_ids = [
  # "<entra-group-object-id: internal readers>",
]
create_entra_app = true

# Monitoring (one switch for all of it; cannot be false in prod)
enable_monitoring              = true
log_retention_days             = 180
monitoring_query_from_internet = true # false = dashboards and log queries only from the APEX network
alert_email_receivers = [
  # "alerts@example.com",
]
alert_thresholds = {
  availability_percent = 95
}
export_activity_log         = false
enable_service_health_alert = true # false in all but one environment sharing a subscription

monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: service owners>",
]
monitoring_operator_principal_ids = [
  # "<entra-group-object-id: operations>",
]

# DEV environment. Replace every <...> placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000001" # <dev subscription id>
tenant_id       = "00000000-0000-0000-0000-000000000000" # <tenant id>

environment = "dev"
location    = "westeurope"
workload    = "pca"
instance    = "001"

governance_tags = {
  owner               = "<owner team>"
  cost_centre         = "<cost centre>"
  data_classification = "Internal"
  support             = "<support group or email>"
}

enable_delete_lock = false
monthly_budget     = 50
budget_contact_emails = [
  # "finance@example.com",
]

# Network: take the ranges from the IP plan; they must not overlap the hub or other spokes.
vnet_address_space           = ["10.60.0.0/24"]
container_apps_subnet_prefix = "10.60.0.0/27"
# dns_servers            = ["<hub DNS resolver IP>"]
# hub_virtual_network_id = "/subscriptions/<hub sub>/resourceGroups/<hub rg>/providers/Microsoft.Network/virtualNetworks/<hub vnet>"
# use_hub_gateway        = true

# Sign-in: only members of these groups can open the app.
allowed_group_ids = [
  "00000000-0000-0000-0000-000000000000", # <entra-group-object-id: app users>
]

# Resilience. Zone redundancy is fixed at creation; the registry needs Premium for it.
zone_redundancy_enabled          = false
registry_sku                     = "Basic"
registry_zone_redundancy_enabled = false

# Application. Leave false for the first apply, push the first image, then set true.
create_container_app = false
image_repository     = "python-mvc-app"
initial_image_tag    = "initial"
min_replicas         = 1
max_replicas         = 1
app_settings = {
  APP_MAX_UPLOAD_MB = "10"
}

# Monitoring
log_retention_days = 30
alert_email_receivers = [
  # "alerts@example.com",
]
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: developers>",
]

# QA environment. Replace every <...> placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000002" # <qa subscription id>
tenant_id       = "00000000-0000-0000-0000-000000000000" # <tenant id>

environment = "qa"
location    = "westeurope"
workload    = "pcds"
instance    = "001"

governance_tags = {
  owner               = "<owner team>"
  cost_centre         = "<cost centre>"
  data_classification = "Internal"
  support             = "<support group or email>"
}

enable_delete_lock = false
monthly_budget     = 100
budget_contact_emails = [
  # "finance@example.com",
]

# Network: take the ranges from the IP plan; they must not overlap the hub or other spokes.
vnet_address_space              = ["10.61.1.0/24"]
container_apps_subnet_prefix    = "10.61.1.0/27"
postgresql_subnet_prefix        = "10.61.1.32/28"
private_endpoints_subnet_prefix = "10.61.1.48/28"
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

# Database. HA is fixed at creation and needs a non-Burstable sku_name.
postgresql_sku_name                     = "B_Standard_B1ms"
postgresql_storage_mb                   = 32768
postgresql_backup_retention_days        = 7
postgresql_geo_redundant_backup_enabled = false
postgresql_ha_enabled                   = false

# Storage (images).
storage_replication_type = "ZRS"

# Key Vault: Terraform needs data-plane access to write the generated secrets.
# key_vault_allowed_ip_ranges = ["<your public IP>/32"]

# Application. Leave false for the first apply, push the first image, then set true.
create_container_app = false
image_repository     = "python-crud-app"
initial_image_tag    = "initial"
min_replicas          = 1
max_replicas           = 1
app_settings = {
  APP_MAX_UPLOAD_MB = "10"
}
seed_admin_username = "admin"
seed_demo_username  = "demo"

# Monitoring
log_retention_days = 30
alert_email_receivers = [
  # "alerts@example.com",
]
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: developers>",
]

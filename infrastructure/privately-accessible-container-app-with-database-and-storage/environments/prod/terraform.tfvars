# PROD environment. Replace every <...> placeholder before the first apply.

subscription_id = "00000000-0000-0000-0000-000000000004" # <prod subscription id>
tenant_id       = "00000000-0000-0000-0000-000000000000" # <tenant id>

environment = "prod"
location    = "westeurope"
workload    = "pcds"
instance    = "001"

governance_tags = {
  owner               = "<owner team>"
  cost_centre         = "<cost centre>"
  data_classification = "Internal"
  support             = "<support group or email>"
}

enable_delete_lock = true
monthly_budget     = 500
budget_contact_emails = [
  # "finance@example.com",
]

# Network: take the ranges from the IP plan; they must not overlap the hub or other spokes.
vnet_address_space              = ["10.61.3.0/24"]
container_apps_subnet_prefix    = "10.61.3.0/27"
postgresql_subnet_prefix        = "10.61.3.32/28"
private_endpoints_subnet_prefix = "10.61.3.48/28"
# dns_servers            = ["<hub DNS resolver IP>"]
# hub_virtual_network_id = "/subscriptions/<hub sub>/resourceGroups/<hub rg>/providers/Microsoft.Network/virtualNetworks/<hub vnet>"
# use_hub_gateway        = true

# Sign-in: only members of these groups can open the app.
allowed_group_ids = [
  "00000000-0000-0000-0000-000000000000", # <entra-group-object-id: app users>
]

# Resilience. Zone redundancy is fixed at creation; the registry needs Premium for it.
zone_redundancy_enabled          = true
registry_sku                     = "Basic"
registry_zone_redundancy_enabled = false

# Database. HA is fixed at creation and needs a non-Burstable sku_name.
postgresql_sku_name                     = "GP_Standard_D2ds_v5"
postgresql_storage_mb                   = 32768
postgresql_backup_retention_days        = 35
postgresql_geo_redundant_backup_enabled = true
postgresql_ha_enabled                   = true
postgresql_ha_mode                      = "ZoneRedundant"
postgresql_zone                         = "1"
postgresql_standby_zone                 = "2"

# Storage (images).
storage_replication_type           = "GZRS"
key_vault_purge_protection_enabled = true

# Key Vault: Terraform needs data-plane access to write the generated secrets.
# key_vault_allowed_ip_ranges = ["<your public IP>/32"]

# Application. Leave false for the first apply, push the first image, then set true.
create_container_app = false
image_repository     = "python-crud-app"
initial_image_tag    = "initial"
min_replicas         = 2 # one per zone at least, so a zone failure leaves a replica serving
max_replicas         = 2
app_settings = {
  APP_MAX_UPLOAD_MB = "10"
}
seed_admin_username = "admin"
seed_demo_username  = "demo"

# Monitoring
log_retention_days = 180
alert_email_receivers = [
  # "alerts@example.com",
]
monitoring_viewer_principal_ids = [
  # "<entra-group-object-id: developers>",
]

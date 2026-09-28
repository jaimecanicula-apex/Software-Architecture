# Privately accessible container app with its own database and image
# storage, for internal users only.
#
#   User on the corporate network --hub peering + private DNS--> internal load balancer
#     --> Container App (Entra sign-in required, assigned groups only)
#     --> app login (username/password) --> container on port 8000
#   Container App --managed identity--> Key Vault (DB password, session secret, seed passwords)
#   Container App --password from Key Vault--> PostgreSQL Flexible Server (VNet-integrated)
#   Container App --managed identity, no keys--> Blob storage (private endpoint)

module "naming" {
  source = "../../modules/naming"

  workload    = var.workload
  environment = var.environment
  location    = var.location
  instance    = var.instance
}

locals {
  tags = merge(
    {
      environment           = var.environment
      application            = var.application_name
      workload                = var.workload
      audience                = "internal"
      owner                    = var.governance_tags.owner
      "cost-centre"            = var.governance_tags.cost_centre
      "data-classification"    = var.governance_tags.data_classification
      support                  = var.governance_tags.support
      "managed-by"             = "terraform"
    },
    var.extra_tags,
  )

  auth_secret_name        = "microsoft-provider-authentication-secret"
  db_password_secret_name = "db-password"
  flask_secret_name       = "flask-secret-key"
  seed_admin_secret_name  = "seed-admin-password"
  seed_demo_secret_name   = "seed-demo-password"
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group
  location = var.location
  tags     = local.tags
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------- network

module "network" {
  source = "../../modules/network"

  name                             = module.naming.virtual_network
  resource_group_name              = azurerm_resource_group.this.name
  location                         = var.location
  address_space                    = var.vnet_address_space
  container_apps_subnet_name       = module.naming.subnet_container_apps
  nsg_name                         = module.naming.nsg_container_apps
  container_apps_subnet_prefix     = var.container_apps_subnet_prefix
  postgresql_subnet_name           = module.naming.subnet_postgresql
  postgresql_subnet_prefix         = var.postgresql_subnet_prefix
  postgresql_nsg_name              = module.naming.nsg_postgresql
  private_endpoints_subnet_name    = module.naming.subnet_private_endpoints
  private_endpoints_subnet_prefix  = var.private_endpoints_subnet_prefix
  private_endpoints_nsg_name       = module.naming.nsg_private_endpoints
  dns_servers                      = var.dns_servers
  hub_virtual_network_id           = var.hub_virtual_network_id
  use_hub_gateway                  = var.use_hub_gateway
  tags                             = local.tags
}

locals {
  dns_link_targets = merge(
    { spoke = module.network.virtual_network_id },
    var.hub_virtual_network_id == null ? {} : { hub = var.hub_virtual_network_id },
  )
}

# ---------------------------------------------------------------- private DNS

resource "azurerm_private_dns_zone" "postgresql" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  for_each = local.dns_link_targets

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = each.value
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  for_each = local.dns_link_targets

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = each.value
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  for_each = local.dns_link_targets

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = each.value
  tags                  = local.tags
}

# ---------------------------------------------------------------- generated secrets

resource "random_password" "db_admin" {
  length  = 32
  special = false # keeps the value safe to embed in a connection string
}

resource "random_password" "flask_secret" {
  length = 48
}

resource "random_password" "seed_admin" {
  length = 20
}

resource "random_password" "seed_demo" {
  length = 20
}

# ---------------------------------------------------------------- database

module "postgresql" {
  source = "../../modules/postgresql"

  name                 = module.naming.postgresql_server
  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  delegated_subnet_id  = module.network.postgresql_subnet_id
  private_dns_zone_id  = azurerm_private_dns_zone.postgresql.id

  postgresql_version            = var.postgresql_version
  sku_name                      = var.postgresql_sku_name
  storage_mb                    = var.postgresql_storage_mb
  backup_retention_days         = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled  = var.postgresql_geo_redundant_backup_enabled
  ha_enabled                    = var.postgresql_ha_enabled
  ha_mode                       = var.postgresql_ha_mode
  zone                          = var.postgresql_zone
  standby_zone                  = var.postgresql_standby_zone

  administrator_login    = var.postgresql_administrator_login
  administrator_password = random_password.db_admin.result

  tags = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

# ---------------------------------------------------------------- storage

module "storage" {
  source = "../../modules/storage"

  name                        = module.naming.storage_account
  resource_group_name         = azurerm_resource_group.this.name
  location                    = var.location
  private_endpoint_subnet_id  = module.network.private_endpoints_subnet_id
  private_dns_zone_id         = azurerm_private_dns_zone.storage.id
  replication_type            = var.storage_replication_type
  soft_delete_retention_days  = var.storage_soft_delete_retention_days
  reader_writer_principal_id  = module.container_app.managed_identity_principal_id

  tags = local.tags
}

# ---------------------------------------------------------------- secrets storage

module "key_vault" {
  source = "../../modules/key-vault"

  name                        = module.naming.key_vault
  resource_group_name         = azurerm_resource_group.this.name
  location                    = var.location
  tenant_id                   = var.tenant_id
  private_endpoint_subnet_id  = module.network.private_endpoints_subnet_id
  private_dns_zone_id         = azurerm_private_dns_zone.key_vault.id
  purge_protection_enabled    = var.key_vault_purge_protection_enabled
  allowed_ip_ranges           = var.key_vault_allowed_ip_ranges

  writer_principal_id = data.azurerm_client_config.current.object_id
  reader_principal_id = module.container_app.managed_identity_principal_id

  secrets = merge(
    {
      (local.db_password_secret_name) = random_password.db_admin.result
      (local.flask_secret_name)       = random_password.flask_secret.result
      (local.seed_admin_secret_name)  = random_password.seed_admin.result
      (local.seed_demo_secret_name)   = random_password.seed_demo.result
    },
    var.create_container_app ? {
      (local.auth_secret_name) = module.entra_app[0].client_secret
      "appinsights-connection" = module.monitoring.application_insights_connection_string
    } : {},
  )

  tags = local.tags
}

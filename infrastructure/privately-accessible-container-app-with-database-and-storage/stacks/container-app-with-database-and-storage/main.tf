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
      application           = var.application_name
      workload              = var.workload
      audience              = "internal"
      owner                 = var.governance_tags.owner
      "cost-centre"         = var.governance_tags.cost_centre
      "data-classification" = var.governance_tags.data_classification
      support               = var.governance_tags.support
      "managed-by"          = "terraform"
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

  name                            = module.naming.virtual_network
  resource_group_name             = azurerm_resource_group.this.name
  location                        = var.location
  address_space                   = var.vnet_address_space
  container_apps_subnet_name      = module.naming.subnet_container_apps
  nsg_name                        = module.naming.nsg_container_apps
  container_apps_subnet_prefix    = var.container_apps_subnet_prefix
  postgresql_subnet_name          = module.naming.subnet_postgresql
  postgresql_subnet_prefix        = var.postgresql_subnet_prefix
  postgresql_nsg_name             = module.naming.nsg_postgresql
  private_endpoints_subnet_name   = module.naming.subnet_private_endpoints
  private_endpoints_subnet_prefix = var.private_endpoints_subnet_prefix
  private_endpoints_nsg_name      = module.naming.nsg_private_endpoints
  dns_servers                     = var.dns_servers
  hub_virtual_network_id          = var.hub_virtual_network_id
  use_hub_gateway                 = var.use_hub_gateway
  tags                            = local.tags
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

  name                = module.naming.postgresql_server
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  delegated_subnet_id = module.network.postgresql_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgresql.id

  postgresql_version           = var.postgresql_version
  sku_name                     = var.postgresql_sku_name
  storage_mb                   = var.postgresql_storage_mb
  backup_retention_days        = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled = var.postgresql_geo_redundant_backup_enabled
  ha_enabled                   = var.postgresql_ha_enabled
  ha_mode                      = var.postgresql_ha_mode
  zone                         = var.postgresql_zone
  standby_zone                 = var.postgresql_standby_zone

  administrator_login    = var.postgresql_administrator_login
  administrator_password = random_password.db_admin.result

  tags = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

# ---------------------------------------------------------------- storage

module "storage" {
  source = "../../modules/storage"

  name                       = module.naming.storage_account
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = azurerm_private_dns_zone.storage.id
  replication_type           = var.storage_replication_type
  soft_delete_retention_days = var.storage_soft_delete_retention_days
  reader_writer_principal_id = module.container_app.managed_identity_principal_id

  tags = local.tags
}

# ---------------------------------------------------------------- secrets storage

module "key_vault" {
  source = "../../modules/key-vault"

  name                       = module.naming.key_vault
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  tenant_id                  = var.tenant_id
  private_endpoint_subnet_id = module.network.private_endpoints_subnet_id
  private_dns_zone_id        = azurerm_private_dns_zone.key_vault.id
  purge_protection_enabled   = var.key_vault_purge_protection_enabled
  allowed_ip_ranges          = var.key_vault_allowed_ip_ranges

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

# ---------------------------------------------------------------- monitoring

module "monitoring" {
  source = "../../modules/monitoring"

  resource_group_name       = azurerm_resource_group.this.name
  resource_group_id         = azurerm_resource_group.this.id
  location                  = var.location
  log_analytics_name        = module.naming.log_analytics
  application_insights_name = module.naming.application_insights
  action_group_name         = module.naming.action_group
  action_group_short_name   = module.naming.action_group_short
  log_retention_days        = var.log_retention_days
  log_daily_quota_gb        = var.log_daily_quota_gb
  alert_email_receivers     = var.alert_email_receivers
  viewer_principal_ids      = var.monitoring_viewer_principal_ids

  postgresql_server_id                     = module.postgresql.server_id
  key_vault_id                             = module.key_vault.id
  storage_account_id                       = module.storage.id
  postgresql_cpu_alert_threshold           = var.postgresql_cpu_alert_threshold
  storage_used_capacity_alert_threshold_gb = var.storage_used_capacity_alert_threshold_gb

  tags = local.tags
}

# ---------------------------------------------------------------- hosting

module "container_app" {
  source = "../../modules/container-app"

  resource_group_name          = azurerm_resource_group.this.name
  location                     = var.location
  environment_name             = module.naming.container_apps_environment
  container_app_name           = module.naming.container_app
  registry_name                = module.naming.container_registry
  managed_identity_name        = module.naming.managed_identity
  subnet_id                    = module.network.container_apps_subnet_id
  dns_zone_virtual_network_ids = local.dns_link_targets
  log_analytics_workspace_id   = module.monitoring.log_analytics_workspace_id
  zone_redundancy_enabled      = var.zone_redundancy_enabled
  registry_sku                 = var.registry_sku

  registry_zone_redundancy_enabled = var.registry_zone_redundancy_enabled

  create_container_app = var.create_container_app
  image_repository     = var.image_repository
  initial_image_tag    = var.initial_image_tag
  cpu                  = var.container_cpu
  memory               = var.container_memory
  min_replicas         = var.min_replicas
  max_replicas         = var.max_replicas

  environment_variables = merge(var.app_settings, {
    DB_HOST                    = module.postgresql.fqdn
    DB_NAME                    = module.postgresql.database_name
    DB_USER                    = var.postgresql_administrator_login
    AZURE_STORAGE_ACCOUNT_NAME = module.storage.account_name
    AZURE_STORAGE_CONTAINER    = "images"
    SEED_ADMIN_USERNAME        = var.seed_admin_username
    SEED_DEMO_USERNAME         = var.seed_demo_username
  })

  secrets = var.create_container_app ? {
    (local.auth_secret_name)        = { key_vault_secret_id = module.key_vault.secret_ids[local.auth_secret_name] }
    "appinsights-connection"        = { key_vault_secret_id = module.key_vault.secret_ids["appinsights-connection"] }
    (local.db_password_secret_name) = { key_vault_secret_id = module.key_vault.secret_ids[local.db_password_secret_name] }
    (local.flask_secret_name)       = { key_vault_secret_id = module.key_vault.secret_ids[local.flask_secret_name] }
    (local.seed_admin_secret_name)  = { key_vault_secret_id = module.key_vault.secret_ids[local.seed_admin_secret_name] }
    (local.seed_demo_secret_name)   = { key_vault_secret_id = module.key_vault.secret_ids[local.seed_demo_secret_name] }
  } : {}

  secret_environment_variables = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = "appinsights-connection"
    DB_PASSWORD                           = local.db_password_secret_name
    APP_SECRET_KEY                        = local.flask_secret_name
    SEED_ADMIN_PASSWORD                   = local.seed_admin_secret_name
    SEED_DEMO_PASSWORD                    = local.seed_demo_secret_name
  }

  tags = local.tags
}

check "zone_redundancy_has_replicas_to_spread" {
  assert {
    condition     = !var.zone_redundancy_enabled || var.min_replicas >= 2
    error_message = "zone_redundancy_enabled is on but min_replicas is below 2: the one replica sits in one zone and must be rescheduled if that zone fails."
  }
}

# Mirrors modules/postgresql's own "ha_needs_non_burstable_sku" check: a
# terraform test's expect_failures can only target a checkable object in the
# configuration under test, not one inside a child module, so the same guard
# is restated here to be assertable from the stack's own test suite.
check "postgresql_ha_needs_non_burstable_sku" {
  assert {
    condition     = !var.postgresql_ha_enabled || !startswith(var.postgresql_sku_name, "B_")
    error_message = "postgresql_ha_enabled needs a General Purpose or Memory Optimized postgresql_sku_name; Burstable (B_*) has no standby."
  }
}

# ---------------------------------------------------------------- sign-in

module "entra_app" {
  source = "../../modules/entra-app-auth"
  count  = var.create_container_app ? 1 : 0

  display_name        = module.naming.entra_app
  site_host_name      = module.container_app.container_app_fqdn
  allowed_group_ids   = var.allowed_group_ids
  assignment_required = true
  owners              = var.entra_app_owners
}

resource "azapi_resource" "sign_in" {
  count = var.create_container_app ? 1 : 0

  type      = "Microsoft.App/containerApps/authConfigs@2024-03-01"
  name      = "current"
  parent_id = module.container_app.container_app_id

  body = {
    properties = {
      platform = { enabled = true }
      globalValidation = {
        unauthenticatedClientAction = "RedirectToLoginPage"
        redirectToProvider          = "azureactivedirectory"
        excludedPaths               = ["/healthz"]
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            clientId                = module.entra_app[0].client_id
            clientSecretSettingName = local.auth_secret_name
            openIdIssuer            = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------- alerts

resource "azurerm_monitor_metric_alert" "restarts" {
  count = var.create_container_app ? 1 : 0

  name                = "alert-restarts-${module.naming.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [module.container_app.container_app_id]
  description         = "The container restarted: it crashed or failed its health probe."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "RestartCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = module.monitoring.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "server_errors" {
  count = var.create_container_app ? 1 : 0

  name                = "alert-5xx-${module.naming.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [module.container_app.container_app_id]
  description         = "The app returned more than 5 server errors in 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = module.monitoring.action_group_id
  }
}

# ---------------------------------------------------------------- governance

resource "azurerm_management_lock" "resource_group" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-cannot-delete"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects the ${var.environment} private container app with database and storage. Remove through change control only."

  depends_on = [module.container_app, module.monitoring, module.postgresql, module.storage, module.key_vault, azapi_resource.sign_in]
}

resource "azurerm_consumption_budget_resource_group" "this" {
  count = var.monthly_budget > 0 ? 1 : 0

  name              = module.naming.budget
  resource_group_id = azurerm_resource_group.this.id
  amount            = var.monthly_budget
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
    contact_groups = [module.monitoring.action_group_id]
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
    contact_groups = [module.monitoring.action_group_id]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}

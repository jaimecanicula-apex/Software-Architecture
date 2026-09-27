# Privately accessible container app, for internal users only.
#
#   User on the corporate network --hub peering + private DNS--> internal load balancer
#     --> Container App (Entra sign-in required, assigned groups only) --> container on port 8000
#   Container logs --> Log Analytics ; requests and exceptions --> Application Insights
#
# Nothing in this design is reachable from the internet. Uploads and outputs
# stay in memory, so there is no storage account or database.

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

  # Name of the container app secret that holds the sign-in client secret.
  auth_secret_name = "microsoft-provider-authentication-secret"
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- network

module "network" {
  source = "../../modules/network"

  name                         = module.naming.virtual_network
  resource_group_name          = azurerm_resource_group.this.name
  location                     = var.location
  address_space                = var.vnet_address_space
  container_apps_subnet_name   = module.naming.subnet_container_apps
  nsg_name                     = module.naming.nsg_container_apps
  container_apps_subnet_prefix = var.container_apps_subnet_prefix
  dns_servers                  = var.dns_servers
  hub_virtual_network_id       = var.hub_virtual_network_id
  use_hub_gateway              = var.use_hub_gateway
  tags                         = local.tags
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
  tags                      = local.tags
}

# ---------------------------------------------------------------- hosting

module "container_app" {
  source = "../../modules/container-app"

  resource_group_name   = azurerm_resource_group.this.name
  location              = var.location
  environment_name      = module.naming.container_apps_environment
  container_app_name    = module.naming.container_app
  registry_name         = module.naming.container_registry
  managed_identity_name = module.naming.managed_identity
  subnet_id             = module.network.container_apps_subnet_id
  dns_zone_virtual_network_ids = merge(
    { spoke = module.network.virtual_network_id },
    var.hub_virtual_network_id == null ? {} : { hub = var.hub_virtual_network_id },
  )
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  zone_redundancy_enabled    = var.zone_redundancy_enabled
  registry_sku               = var.registry_sku

  registry_zone_redundancy_enabled = var.registry_zone_redundancy_enabled

  create_container_app = var.create_container_app
  image_repository     = var.image_repository
  initial_image_tag    = var.initial_image_tag
  cpu                  = var.container_cpu
  memory               = var.container_memory
  min_replicas         = var.min_replicas
  max_replicas         = var.max_replicas

  environment_variables = var.app_settings
  secrets = var.create_container_app ? {
    (local.auth_secret_name) = module.entra_app[0].client_secret
    "appinsights-connection" = module.monitoring.application_insights_connection_string
  } : {}
  secret_environment_variables = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = "appinsights-connection"
  }

  tags = local.tags
}

# Zone redundancy spreads replicas across zones, so a single replica gains little.
check "zone_redundancy_has_replicas_to_spread" {
  assert {
    condition     = !var.zone_redundancy_enabled || var.min_replicas >= 2
    error_message = "zone_redundancy_enabled is on but min_replicas is below 2: the one replica sits in one zone and must be rescheduled if that zone fails."
  }
}

# ---------------------------------------------------------------- sign-in

# Created with the app, because the redirect URI needs the app's host name.
module "entra_app" {
  source = "../../modules/entra-app-auth"
  count  = var.create_container_app ? 1 : 0

  display_name        = module.naming.entra_app
  site_host_name      = module.container_app.container_app_fqdn
  allowed_group_ids   = var.allowed_group_ids
  assignment_required = true
  owners              = var.entra_app_owners
}

# Container Apps built-in authentication: every request needs an Entra sign-in,
# except the health endpoint. The app receives the user in X-MS-CLIENT-PRINCIPAL-* headers.
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
  notes      = "Protects the ${var.environment} private container app. Remove through change control only."

  depends_on = [module.container_app, module.monitoring, azapi_resource.sign_in]
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

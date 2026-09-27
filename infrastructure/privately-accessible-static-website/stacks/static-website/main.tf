# Privately accessible static website, for internal users only (anyone signing
# in with APEX Entra: employees, APEX companies, contractors).
#
#   APEX user on the corporate network --private DNS--> private endpoint
#     --> Static Web App (public access off, APEX Entra sign-in required)
#   In-VNet probe --> site ; probe + diagnostics --> Monitor Private Link --> Log Analytics
#
# Nothing in this design is reachable from the internet.

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

  monitor_dns_zones = [
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.blob.core.windows.net",
  ]
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- network

module "network" {
  source = "../../modules/network"

  name                           = module.naming.virtual_network
  resource_group_name            = azurerm_resource_group.this.name
  location                       = var.location
  address_space                  = var.vnet_address_space
  subnet_names                   = { private_endpoints = module.naming.subnet_private_endpoints, probe = module.naming.subnet_probe }
  nsg_names                      = { private_endpoints = module.naming.nsg_private_endpoints, probe = module.naming.nsg_probe }
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix
  probe_subnet_prefix            = var.probe_subnet_prefix
  dns_servers                    = var.dns_servers
  private_dns_zones              = var.enable_monitoring ? local.monitor_dns_zones : []
  hub_virtual_network_id         = var.hub_virtual_network_id
  use_hub_gateway                = var.use_hub_gateway
  tags                           = local.tags
}

# ---------------------------------------------------------------- sign-in

module "entra_app" {
  source = "../../modules/entra-app-auth"
  count  = var.create_entra_app ? 1 : 0

  display_name        = module.naming.entra_app
  site_host_name      = module.static_web_app.default_host_name
  allowed_group_ids   = var.allowed_group_ids
  assignment_required = true
  owners              = var.entra_app_owners
}

locals {
  entra_client_id     = var.create_entra_app ? module.entra_app[0].client_id : var.existing_entra_client_id
  entra_client_secret = var.create_entra_app ? module.entra_app[0].client_secret : var.existing_entra_client_secret
}

# ---------------------------------------------------------------- hosting

module "static_web_app" {
  source = "../../modules/static-web-app"

  name                          = module.naming.static_web_app
  resource_group_name           = azurerm_resource_group.this.name
  location                      = var.location
  sku                           = "Standard" # private endpoints and custom auth need Standard
  preview_environments_enabled  = var.preview_environments_enabled
  public_network_access_enabled = false
  tags                          = local.tags

  app_settings = {
    AZURE_CLIENT_ID     = local.entra_client_id
    AZURE_CLIENT_SECRET = local.entra_client_secret
  }
}

locals {
  # Static Web App hosts look like <name>.<partition>.azurestaticapps.net; the
  # private DNS zone follows the partition.
  swa_partition = try(regex("\\.([0-9]+)\\.azurestaticapps\\.net$", module.static_web_app.default_host_name)[0], null)
  swa_dns_zone  = local.swa_partition == null ? "privatelink.azurestaticapps.net" : "privatelink.${local.swa_partition}.azurestaticapps.net"
}

resource "azurerm_private_dns_zone" "site" {
  name                = local.swa_dns_zone
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "site_spoke" {
  name                  = "link-${module.naming.virtual_network}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.site.name
  virtual_network_id    = module.network.virtual_network_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "site_hub" {
  count = var.hub_virtual_network_id == null ? 0 : 1

  name                  = "link-hub"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.site.name
  virtual_network_id    = var.hub_virtual_network_id
  registration_enabled  = false
  tags                  = local.tags
}

module "site_endpoint" {
  source = "../../modules/private-endpoint"

  name                 = module.naming.private_endpoint_site
  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  subnet_id            = module.network.private_endpoint_subnet_id
  target_resource_id   = module.static_web_app.id
  subresource_names    = ["staticSites"]
  private_dns_zone_ids = [azurerm_private_dns_zone.site.id]
  tags                 = local.tags
}

# ---------------------------------------------------------------- monitoring

module "monitoring" {
  source = "../../modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  resource_group_name       = azurerm_resource_group.this.name
  resource_group_id         = azurerm_resource_group.this.id
  location                  = var.location
  name_suffix               = module.naming.suffix
  log_analytics_name        = module.naming.log_analytics
  application_insights_name = module.naming.application_insights
  action_group_name         = module.naming.action_group
  action_group_short_name   = module.naming.action_group_short
  log_retention_days        = var.log_retention_days
  log_daily_quota_gb        = var.log_daily_quota_gb

  # Private site: no Front Door, no internet web tests; the in-VNet probe reports instead.
  front_door_enabled             = false
  availability_tests             = {}
  custom_availability_test_names = ["site"]
  internet_ingestion_enabled     = false
  internet_query_enabled         = var.monitoring_query_from_internet

  alert_email_receivers        = var.alert_email_receivers
  alert_webhook_receivers      = var.alert_webhook_receivers
  alert_thresholds             = var.alert_thresholds
  export_activity_log          = var.export_activity_log
  service_health_alert_enabled = var.enable_service_health_alert

  viewer_principal_ids   = var.monitoring_viewer_principal_ids
  operator_principal_ids = var.monitoring_operator_principal_ids

  tags = local.tags
}

module "monitor_private_link" {
  source = "../../modules/monitor-private-link"
  count  = var.enable_monitoring ? 1 : 0

  name                = module.naming.private_link_scope
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = module.network.private_endpoint_subnet_id
  linked_resource_ids = {
    law  = module.monitoring[0].log_analytics_workspace_id
    appi = module.monitoring[0].application_insights_id
  }
  private_dns_zone_ids = [for z in local.monitor_dns_zones : module.network.private_dns_zone_ids[z]]
  query_access_mode    = var.monitoring_query_from_internet ? "Open" : "PrivateOnly"
  tags                 = local.tags
}

module "availability_probe" {
  source = "../../modules/availability-probe"
  count  = var.enable_monitoring ? 1 : 0

  name_suffix                            = module.naming.suffix
  resource_group_name                    = azurerm_resource_group.this.name
  location                               = var.location
  subnet_id                              = module.network.probe_subnet_id
  log_analytics_workspace_id             = module.monitoring[0].log_analytics_workspace_id
  application_insights_connection_string = module.monitoring[0].application_insights_connection_string
  cron_expression                        = var.probe_cron
  zone_redundancy_enabled                = var.probe_zone_redundancy_enabled
  image                                  = var.probe_image
  tags                                   = local.tags

  # /healthz.html is the one anonymous route; everything else needs APEX sign-in.
  tests = {
    site = { url = "https://${module.static_web_app.default_host_name}/healthz.html" }
  }

  depends_on = [module.site_endpoint, module.monitor_private_link]
}

# ---------------------------------------------------------------- governance

resource "azurerm_management_lock" "resource_group" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-cannot-delete"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects the ${var.environment} internal static website. Remove through change control only."

  depends_on = [module.static_web_app, module.site_endpoint, module.monitoring, module.monitor_private_link, module.availability_probe]
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
    contact_groups = module.monitoring[*].action_group_id
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = var.budget_contact_emails
    contact_groups = module.monitoring[*].action_group_id
  }

  lifecycle {
    ignore_changes = [time_period]

    precondition {
      condition     = var.enable_monitoring || length(var.budget_contact_emails) > 0
      error_message = "With monitoring off, the budget has no action group: set budget_contact_emails."
    }
  }
}

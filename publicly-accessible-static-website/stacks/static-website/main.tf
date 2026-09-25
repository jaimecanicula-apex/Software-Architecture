# Static website stack: one root module, deployed once per environment
# with environments/<env>/terraform.tfvars and environments/<env>/backend.hcl.
#
#   Visitor -> Front Door (+ WAF) -> Static Web App (build-free app/ folder)
#   Everything -> Log Analytics / Application Insights -> alerts, workbook

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
      owner                 = var.governance_tags.owner
      "cost-centre"         = var.governance_tags.cost_centre
      "data-classification" = var.governance_tags.data_classification
      support               = var.governance_tags.support
      "managed-by"          = "terraform"
    },
    var.extra_tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group
  location = var.location
  tags     = local.tags
}

module "static_web_app" {
  source = "../../modules/static-web-app"

  name                         = module.naming.static_web_app
  resource_group_name          = azurerm_resource_group.this.name
  location                     = var.location
  sku                          = var.static_web_app_sku
  preview_environments_enabled = var.preview_environments_enabled
  tags                         = local.tags
}

module "front_door" {
  source = "../../modules/front-door"
  count  = var.enable_front_door ? 1 : 0

  profile_name        = module.naming.front_door_profile
  endpoint_name       = module.naming.front_door_endpoint
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = var.front_door_sku
  origin_host_name    = module.static_web_app.default_host_name
  custom_domains      = { for k, d in var.custom_domains : k => { host_name = d.host_name, dns_zone_id = d.dns_zone_id } }
  tags                = local.tags
}

module "waf" {
  source = "../../modules/front-door-waf"
  count  = var.enable_front_door ? 1 : 0

  name                  = module.naming.waf_policy
  resource_group_name   = azurerm_resource_group.this.name
  sku_name              = var.front_door_sku
  front_door_profile_id = module.front_door[0].profile_id
  domain_ids            = concat([module.front_door[0].endpoint_id], values(module.front_door[0].custom_domain_ids))
  mode                  = var.waf_mode
  rate_limit_per_minute = var.waf_rate_limit_per_minute
  blocked_country_codes = var.waf_blocked_country_codes
  tags                  = local.tags
}

locals {
  public_host_name = var.enable_front_door ? module.front_door[0].endpoint_host_name : module.static_web_app.default_host_name

  availability_tests = merge(
    { site = "https://${local.public_host_name}/" },
    { for k, d in var.custom_domains : k => "https://${d.host_name}/" if d.monitor },
  )
}

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

  front_door_enabled    = var.enable_front_door
  front_door_profile_id = var.enable_front_door ? module.front_door[0].profile_id : null

  availability_tests          = local.availability_tests
  availability_test_locations = coalesce(var.availability_test_locations, ["emea-nl-ams-azr", "emea-gb-db3-azr", "emea-ru-msa-edge", "us-va-ash-azr", "apac-sg-sin-azr"])

  alert_email_receivers        = var.alert_email_receivers
  alert_webhook_receivers      = var.alert_webhook_receivers
  alert_thresholds             = var.alert_thresholds
  export_activity_log          = var.export_activity_log
  service_health_alert_enabled = var.enable_service_health_alert

  viewer_principal_ids   = var.monitoring_viewer_principal_ids
  operator_principal_ids = var.monitoring_operator_principal_ids

  tags = local.tags
}

resource "azurerm_management_lock" "resource_group" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-cannot-delete"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects the ${var.environment} static website. Remove through change control only."

  # Create the lock last so Terraform can finish building everything inside the group.
  depends_on = [module.static_web_app, module.front_door, module.waf, module.monitoring]
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

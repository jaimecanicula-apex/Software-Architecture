# Alert rules. Every rule notifies the Action Group; severity follows Azure Monitor (0 critical .. 4 verbose).

locals {
  t = var.alert_thresholds

  front_door_metric_alerts = var.front_door_enabled ? {
    origin-health = {
      description = "Front Door can no longer reach the Static Web App origin reliably."
      metric      = "OriginHealthPercentage"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = local.t.origin_health_percent
      severity    = 1
    }
    error-5xx = {
      description = "Share of requests answered with a 5xx status is above the threshold."
      metric      = "Percentage5XX"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = local.t.error_5xx_percent
      severity    = 1
    }
    error-4xx = {
      description = "Share of requests answered with a 4xx status is unusually high (broken links or probing)."
      metric      = "Percentage4XX"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = local.t.error_4xx_percent
      severity    = 3
    }
    latency = {
      description = "Average end-to-end latency at the edge is above the threshold (ms)."
      metric      = "TotalLatency"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = local.t.latency_ms
      severity    = 2
    }
  } : {}

  # Internet web tests and in-network probe results share one alert shape.
  availability_names = merge(
    { for k, _ in var.availability_tests : k => azurerm_application_insights_standard_web_test.site[k].name },
    { for n in var.custom_availability_test_names : n => n },
  )

  # High-impact control-plane changes in the resource group.
  critical_operations = {
    static-web-app-deleted = "Microsoft.Web/staticSites/delete"
    front-door-deleted     = "Microsoft.Cdn/profiles/delete"
    waf-policy-changed     = "Microsoft.Network/frontDoorWebApplicationFirewallPolicies/write"
    waf-policy-deleted     = "Microsoft.Network/frontDoorWebApplicationFirewallPolicies/delete"
    role-assignment-added  = "Microsoft.Authorization/roleAssignments/write"
    lock-deleted           = "Microsoft.Authorization/locks/delete"
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  for_each = local.availability_names

  name                = "alert-availability-${each.key}-${var.name_suffix}"
  description         = "Availability test ${each.key} dropped below ${local.t.availability_percent}%."
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights.this.id]
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "availabilityResults/availabilityPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = local.t.availability_percent

    dimension {
      name     = "availabilityResult/name"
      operator = "Include"
      values   = [each.value]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "front_door" {
  for_each = local.front_door_metric_alerts

  name                = "alert-afd-${each.key}-${var.name_suffix}"
  description         = each.value.description
  resource_group_name = var.resource_group_name
  scopes              = [var.front_door_profile_id]
  severity            = each.value.severity
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Cdn/profiles"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

# A probe that stops reporting is an outage nobody would otherwise see.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "probe_silent" {
  for_each = toset(var.custom_availability_test_names)

  name                 = "alert-probe-silent-${each.key}-${var.name_suffix}"
  description          = "No availability result from the in-network probe ${each.key} for 15 minutes: the probe or the network path is down."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_log_analytics_workspace.this.id]
  severity             = 1
  evaluation_frequency = "PT10M"
  window_duration      = "PT15M"
  tags                 = var.tags

  criteria {
    query                   = <<-KQL
      AppAvailabilityResults
      | where Name == "${each.key}"
    KQL
    time_aggregation_method = "Count"
    operator                = "LessThan"
    threshold               = 1

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "waf_blocks" {
  count = var.front_door_enabled ? 1 : 0

  name                 = "alert-waf-blocks-${var.name_suffix}"
  description          = "WAF blocked more than ${local.t.waf_blocks_per_15min} requests in 15 minutes: an attack, or a false positive to tune."
  resource_group_name  = var.resource_group_name
  location             = var.location
  scopes               = [azurerm_log_analytics_workspace.this.id]
  severity             = 2
  evaluation_frequency = "PT15M"
  window_duration      = "PT15M"
  tags                 = var.tags

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where Category == "FrontDoorWebApplicationFirewallLog"
      | where tostring(column_ifexists("action_s", "")) =~ "Block"
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = local.t.waf_blocks_per_15min

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.this.id]
  }

  depends_on = [azurerm_monitor_diagnostic_setting.front_door]
}

resource "azurerm_monitor_activity_log_alert" "critical_change" {
  for_each = local.critical_operations

  name                = "alert-${each.key}-${var.name_suffix}"
  description         = "Control-plane operation ${each.value} ran in ${var.resource_group_name}."
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [var.resource_group_id]
  tags                = var.tags

  criteria {
    category       = "Administrative"
    operation_name = each.value
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_activity_log_alert" "resource_health" {
  name                = "alert-resource-health-${var.name_suffix}"
  description         = "A resource in ${var.resource_group_name} became degraded or unavailable."
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [var.resource_group_id]
  tags                = var.tags

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Degraded", "Unavailable"]
      previous = ["Available"]
      reason   = ["PlatformInitiated", "Unknown"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  count = var.service_health_alert_enabled ? 1 : 0

  name                = "alert-service-health-${var.name_suffix}"
  description         = "Azure service incident, maintenance or security advisory affecting this subscription."
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [data.azurerm_subscription.current.id]
  tags                = var.tags

  criteria {
    category = "ServiceHealth"

    service_health {
      events = ["Incident", "Maintenance", "Security"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

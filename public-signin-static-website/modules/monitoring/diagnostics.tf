# Resource diagnostics into Log Analytics.

resource "azurerm_monitor_diagnostic_setting" "front_door" {
  count = var.front_door_enabled ? 1 : 0

  name                       = "diag-to-log-analytics"
  target_resource_id         = var.front_door_profile_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Subscription Activity Log: deletions, role assignments, policy and service health events.
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  count = var.export_activity_log ? 1 : 0

  name                       = "activity-log-to-${var.log_analytics_name}"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = ["Administrative", "Security", "ServiceHealth", "Alert", "Policy", "ResourceHealth"]
    content {
      category = enabled_log.value
    }
  }
}

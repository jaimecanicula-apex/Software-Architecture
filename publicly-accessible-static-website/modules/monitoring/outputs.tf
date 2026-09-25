output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "application_insights_id" {
  value = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "For optional browser (real-user) telemetry in the site."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "action_group_id" {
  value = azurerm_monitor_action_group.this.id
}

output "workbook_id" {
  value = azurerm_application_insights_workbook.site.id
}

output "workbook_portal_url" {
  description = "Direct link to the dashboard in the Azure portal."
  value       = "https://portal.azure.com/#@/resource${azurerm_application_insights_workbook.site.id}/workbook"
}

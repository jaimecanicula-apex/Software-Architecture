output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "static_web_app_name" {
  value = module.static_web_app.name
}

output "static_web_app_default_host_name" {
  value = module.static_web_app.default_host_name
}

output "static_web_app_deployment_token" {
  description = "Store as AZURE_STATIC_WEB_APPS_API_TOKEN in GitHub or the Azure DevOps variable group. Read with: terraform output -raw static_web_app_deployment_token"
  value       = module.static_web_app.api_key
  sensitive   = true
}

output "public_url" {
  value = "https://${local.public_host_name}/"
}

output "front_door_endpoint_host_name" {
  value = var.enable_front_door ? module.front_door[0].endpoint_host_name : null
}

output "front_door_id" {
  description = "Value of the X-Azure-FDID header the Static Web App must require."
  value       = var.enable_front_door ? module.front_door[0].profile_resource_guid : null
}

output "custom_domain_dns_records" {
  description = "Create these at the DNS provider: the TXT record validates the domain, the CNAME routes traffic."
  value       = var.enable_front_door ? module.front_door[0].custom_domain_validation : {}
}

output "staticwebapp_config_json" {
  description = "Environment-specific staticwebapp.config.json that locks the origin to this Front Door. Write it to app/ in the delivery pipeline."
  value = templatefile("${path.module}/templates/staticwebapp.config.json.tftpl", {
    front_door_enabled = var.enable_front_door
    front_door_id      = var.enable_front_door ? module.front_door[0].profile_resource_guid : ""
    forwarded_hosts = var.enable_front_door ? concat(
      [module.front_door[0].endpoint_host_name],
      [for d in var.custom_domains : d.host_name],
    ) : []
  })
}

output "monitoring_dashboard_url" {
  description = "Azure Monitor workbook with availability, traffic, latency, WAF and alerts."
  value       = one(module.monitoring[*].workbook_portal_url)
}

output "log_analytics_workspace_id" {
  value = one(module.monitoring[*].log_analytics_workspace_id)
}

output "application_insights_connection_string" {
  value     = one(module.monitoring[*].application_insights_connection_string)
  sensitive = true
}

output "action_group_id" {
  value = one(module.monitoring[*].action_group_id)
}

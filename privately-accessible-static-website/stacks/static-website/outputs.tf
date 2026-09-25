output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "static_web_app_name" {
  value = module.static_web_app.name
}

output "private_url" {
  description = "Resolves to the private endpoint from the VNet and any linked hub; unreachable from the internet."
  value       = "https://${module.static_web_app.default_host_name}/"
}

output "private_endpoint_ip" {
  value = module.site_endpoint.private_ip_address
}

output "static_web_app_deployment_token" {
  description = "Store as AZURE_STATIC_WEB_APPS_API_TOKEN for the internal delivery pipeline."
  value       = module.static_web_app.api_key
  sensitive   = true
}

output "staticwebapp_config_json" {
  description = "staticwebapp.config.json for app-internal/: APEX-only sign-in, anonymous /healthz.html for the probe, security headers. Store it as the pipeline's SWA_CONFIG_JSON."
  value = templatefile("${path.module}/templates/staticwebapp.config.json.tftpl", {
    tenant_id = var.tenant_id
  })
}

output "entra_client_id" {
  value = local.entra_client_id
}

output "virtual_network_id" {
  value = module.network.virtual_network_id
}

output "private_dns_zones" {
  description = "Zones the APEX DNS (or hub resolver) must be able to resolve for users to reach the site."
  value       = concat(keys(module.network.private_dns_zone_ids), [azurerm_private_dns_zone.site.name])
}

output "monitoring_dashboard_url" {
  value = one(module.monitoring[*].workbook_portal_url)
}

output "log_analytics_workspace_id" {
  value = one(module.monitoring[*].log_analytics_workspace_id)
}

output "action_group_id" {
  value = one(module.monitoring[*].action_group_id)
}

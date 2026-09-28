output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "container_app_name" {
  value = module.naming.container_app
}

output "app_url" {
  description = "Internal URL. Resolves only on the spoke, the hub and networks that use the hub's DNS."
  value       = var.create_container_app ? "https://${module.container_app.container_app_fqdn}" : null
}

output "registry_login_server" {
  description = "Push images here, e.g. az acr build --registry <name> --image python-crud-app:<tag> content/python-crud-app."
  value       = module.container_app.registry_login_server
}

output "environment_dns" {
  description = "For the hub DNS team: the zone to forward (or link) and the address it resolves to."
  value = {
    zone       = module.container_app.environment_default_domain
    ip_address = module.container_app.environment_static_ip_address
  }
}

output "postgresql_fqdn" {
  value = module.postgresql.fqdn
}

output "storage_account_name" {
  value = module.storage.account_name
}

output "key_vault_id" {
  value = module.key_vault.id
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

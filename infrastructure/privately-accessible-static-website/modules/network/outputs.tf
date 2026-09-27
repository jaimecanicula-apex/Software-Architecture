output "virtual_network_id" {
  value = azurerm_virtual_network.this.id
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "probe_subnet_id" {
  value = azurerm_subnet.probe.id
}

output "private_dns_zone_ids" {
  description = "Zone name => zone ID."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "profile_id" {
  value = azurerm_cdn_frontdoor_profile.this.id
}

output "profile_resource_guid" {
  description = "Front Door ID sent in the X-Azure-FDID header; the Static Web App only accepts requests carrying it."
  value       = azurerm_cdn_frontdoor_profile.this.resource_guid
}

output "endpoint_id" {
  value = azurerm_cdn_frontdoor_endpoint.this.id
}

output "endpoint_host_name" {
  value = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "custom_domain_ids" {
  value = { for k, d in azurerm_cdn_frontdoor_custom_domain.this : k => d.id }
}

output "custom_domain_validation" {
  description = "DNS records to create at the registrar for each custom domain."
  value = {
    for k, d in azurerm_cdn_frontdoor_custom_domain.this : k => {
      host_name    = d.host_name
      txt_record   = "_dnsauth.${d.host_name}"
      txt_value    = d.validation_token
      cname_target = azurerm_cdn_frontdoor_endpoint.this.host_name
    }
  }
}

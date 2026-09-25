# Azure Front Door (Standard/Premium) in front of the Static Web App:
# TLS, custom domains, HTTPS redirect, edge caching and security headers.
# The WAF policy is attached by the front-door-waf module.

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                     = var.profile_name
  resource_group_name      = var.resource_group_name
  sku_name                 = var.sku_name
  response_timeout_seconds = 60
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = var.endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  enabled                  = true
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "site" {
  name                                                      = "og-static-web-app"
  cdn_frontdoor_profile_id                                  = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled                                  = false
  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 10

  health_probe {
    path                = var.health_probe_path
    protocol            = "Https"
    request_type        = "HEAD"
    interval_in_seconds = var.health_probe_interval_seconds
  }

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
}

resource "azurerm_cdn_frontdoor_origin" "site" {
  name                           = "origin-static-web-app"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.site.id
  enabled                        = true
  host_name                      = var.origin_host_name
  origin_host_header             = var.origin_host_name
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  for_each = var.custom_domains

  name                     = "cd-${each.key}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = each.value.host_name
  dns_zone_id              = each.value.dns_zone_id

  tls {
    certificate_type = "ManagedCertificate"
    minimum_version  = "TLS12"
  }
}

resource "azurerm_cdn_frontdoor_rule_set" "security" {
  name                     = "SecurityHeaders"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
}

resource "azurerm_cdn_frontdoor_rule" "security_headers" {
  name                      = "SetSecurityHeaders"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.security.id
  order                     = 1
  behavior_on_match         = "Continue"

  actions {
    dynamic "response_header_action" {
      for_each = var.security_headers
      content {
        header_action = "Overwrite"
        header_name   = response_header_action.key
        value         = response_header_action.value
      }
    }
  }

  depends_on = [
    azurerm_cdn_frontdoor_origin_group.site,
    azurerm_cdn_frontdoor_origin.site,
  ]
}

resource "azurerm_cdn_frontdoor_route" "site" {
  name                            = "route-site"
  cdn_frontdoor_endpoint_id       = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id   = azurerm_cdn_frontdoor_origin_group.site.id
  cdn_frontdoor_origin_ids        = [azurerm_cdn_frontdoor_origin.site.id]
  cdn_frontdoor_rule_set_ids      = [azurerm_cdn_frontdoor_rule_set.security.id]
  cdn_frontdoor_custom_domain_ids = [for d in azurerm_cdn_frontdoor_custom_domain.this : d.id]
  enabled                         = true
  supported_protocols             = ["Http", "Https"]
  patterns_to_match               = ["/*"]
  forwarding_protocol             = "HttpsOnly"
  https_redirect_enabled          = true
  link_to_default_domain          = true

  dynamic "cache" {
    for_each = var.caching_enabled ? [1] : []
    content {
      query_string_caching_behavior = "IgnoreQueryString"
      compression_enabled           = true
      content_types_to_compress = [
        "text/html",
        "text/css",
        "text/plain",
        "text/javascript",
        "application/javascript",
        "application/json",
        "image/svg+xml",
      ]
    }
  }

  depends_on = [azurerm_cdn_frontdoor_rule.security_headers]
}

resource "azurerm_cdn_frontdoor_custom_domain_association" "this" {
  for_each = var.custom_domains

  cdn_frontdoor_custom_domain_id = azurerm_cdn_frontdoor_custom_domain.this[each.key].id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.site.id]
}

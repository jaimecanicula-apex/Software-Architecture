# WAF policy for Front Door, attached to every public domain through a security policy.
# Managed rule sets (DRS, Bot Manager) are only available on the Premium tier;
# the Standard tier gets the custom rules only.

locals {
  is_premium = var.sku_name == "Premium_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  sku_name                          = var.sku_name
  enabled                           = true
  mode                              = var.mode
  custom_block_response_status_code = 403
  tags                              = var.tags

  custom_rule {
    name                           = "RateLimitPerClient"
    enabled                        = true
    priority                       = 100
    type                           = "RateLimitRule"
    action                         = "Block"
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = var.rate_limit_per_minute

    match_condition {
      match_variable = "RequestUri"
      operator       = "BeginsWith"
      match_values   = ["/"]
    }
  }

  dynamic "custom_rule" {
    for_each = length(var.blocked_country_codes) > 0 ? [1] : []
    content {
      name     = "BlockCountries"
      enabled  = true
      priority = 200
      type     = "MatchRule"
      action   = "Block"

      match_condition {
        match_variable = "SocketAddr"
        operator       = "GeoMatch"
        match_values   = var.blocked_country_codes
      }
    }
  }

  dynamic "managed_rule" {
    for_each = local.is_premium ? var.managed_rule_sets : []
    content {
      type    = managed_rule.value.type
      version = managed_rule.value.version
      action  = managed_rule.value.action
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "secpol-waf"
  cdn_frontdoor_profile_id = var.front_door_profile_id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id

      association {
        dynamic "domain" {
          for_each = var.domain_ids
          content {
            cdn_frontdoor_domain_id = domain.value
          }
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

# Multi-region availability tests against the public URLs.
# Each test also fails when the TLS certificate is close to expiry.

resource "azurerm_application_insights_standard_web_test" "site" {
  for_each = var.availability_tests

  name                    = "webtest-${each.key}-${var.name_suffix}"
  description             = "GET ${each.value} returns 200 with a valid certificate."
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id
  geo_locations           = var.availability_test_locations
  frequency               = var.availability_test_frequency_seconds
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  tags                    = var.tags

  request {
    url                              = each.value
    http_verb                        = "GET"
    follow_redirects_enabled         = true
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = var.certificate_expiry_warning_days
  }
}

# Plans with mocked providers, so no Azure access is needed:
#   terraform test -var-file=../../environments/dev/terraform.tfvars
mock_provider "azurerm" {}
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "time" {}

run "monitoring_on" {
  command = plan
  assert {
    condition     = length(module.monitoring) == 1 && length(module.monitor_private_link) == 1 && length(module.availability_probe) == 1
    error_message = "Monitoring resources must be planned by default."
  }
}

run "monitoring_off" {
  command = plan
  variables {
    enable_monitoring     = false
    budget_contact_emails = ["owner@example.com"]
  }
  assert {
    condition     = length(module.monitoring) == 0 && length(module.monitor_private_link) == 0 && length(module.availability_probe) == 0
    error_message = "Monitoring resources must not be planned when enable_monitoring = false."
  }
}

run "monitoring_off_in_prod_is_refused" {
  command = plan
  variables {
    environment              = "prod"
    enable_monitoring        = false
    malware_scanning_enabled = true
  }
  expect_failures = [var.enable_monitoring]
}

run "monitoring_off_needs_budget_contacts" {
  command = plan
  variables {
    enable_monitoring     = false
    budget_contact_emails = []
  }
  expect_failures = [azurerm_consumption_budget_resource_group.this]
}

run "service_health_alert_off" {
  command = plan
  variables {
    enable_service_health_alert = false
  }
  assert {
    condition     = length(module.monitoring) == 1
    error_message = "Turning off the service health alert must keep the rest of monitoring."
  }
}

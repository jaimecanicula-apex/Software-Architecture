# Plans with mocked providers, so no Azure access is needed:
#   terraform test -var-file=../../environments/dev/terraform.tfvars
mock_provider "azurerm" {}
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "time" {}

# Skip creating the app registration: its group assignments cannot be planned
# before the guest group exists (a known first-apply issue, separate from monitoring).
variables {
  create_entra_app             = false
  existing_entra_client_id     = "00000000-0000-0000-0000-000000000002"
  existing_entra_client_secret = "test"
}

run "monitoring_on" {
  command = plan
  assert {
    condition     = length(module.monitoring) == 1
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
    condition     = length(module.monitoring) == 0
    error_message = "Monitoring resources must not be planned when enable_monitoring = false."
  }
}

run "monitoring_off_in_prod_is_refused" {
  command = plan
  variables {
    environment       = "prod"
    enable_monitoring = false
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

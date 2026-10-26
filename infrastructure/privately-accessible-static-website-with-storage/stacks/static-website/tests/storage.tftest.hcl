# File library checks, with mocked providers (no Azure access needed):
#   terraform test -var-file=../../environments/dev/terraform.tfvars
mock_provider "azurerm" {}
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-000000000001" }
  }
}
mock_provider "time" {}

run "storage_is_never_public_and_keyless" {
  command = plan
  assert {
    condition     = module.storage.public_network_access_enabled == false && module.storage.shared_access_key_enabled == false
    error_message = "The file library must have no public access and no account keys."
  }
  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", module.storage.account_name))
    error_message = "The storage account name must be 3-24 lowercase letters and digits."
  }
}

run "storage_is_private_without_monitoring" {
  command = plan
  variables {
    enable_monitoring     = false
    budget_contact_emails = ["owner@example.com"]
  }
  assert {
    condition     = module.storage.public_network_access_enabled == false
    error_message = "The blob private DNS zone must still exist with monitoring off, so the storage endpoint resolves privately."
  }
}

run "malware_scanning_on_in_prod" {
  command = plan
  variables {
    environment              = "prod"
    malware_scanning_enabled = true
  }
  assert {
    condition     = module.storage.malware_scanning_enabled
    error_message = "Malware scanning must be planned when malware_scanning_enabled = true."
  }
}

run "malware_scanning_off_in_prod_is_refused" {
  command = plan
  variables {
    environment              = "prod"
    malware_scanning_enabled = false
  }
  expect_failures = [var.malware_scanning_enabled]
}

run "bad_replication_type_is_refused" {
  command = plan
  variables {
    storage_replication_type = "GRS"
  }
  expect_failures = [var.storage_replication_type]
}


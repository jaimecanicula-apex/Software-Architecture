# Plans with mocked providers, so no Azure access is needed:
#   terraform test -var-file=../../environments/dev/terraform.tfvars
mock_provider "azurerm" {
  mock_resource "azurerm_container_app" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.App/containerApps/ca-test" }
    override_during = plan
  }
  mock_resource "azurerm_postgresql_flexible_server" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-test", fqdn = "psql-test.postgres.database.azure.com" }
    override_during = plan
  }
  mock_resource "azurerm_key_vault" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test" }
    override_during = plan
  }
  mock_resource "azurerm_storage_account" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest" }
    override_during = plan
  }
}
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-0000000000aa" }
  }
}
mock_provider "azapi" {}
mock_provider "time" {}
mock_provider "random" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000001"
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  environment     = "dev"
  location        = "westeurope"

  governance_tags = {
    owner               = "test-team"
    cost_centre         = "TEST"
    data_classification = "Internal"
    support             = "test@example.com"
  }

  vnet_address_space              = ["10.61.0.0/24"]
  container_apps_subnet_prefix    = "10.61.0.0/27"
  postgresql_subnet_prefix        = "10.61.0.32/28"
  private_endpoints_subnet_prefix = "10.61.0.48/28"

  allowed_group_ids   = ["00000000-0000-0000-0000-0000000000bb"]
  postgresql_sku_name = "B_Standard_B1ms"
}

run "first_apply_creates_platform_only" {
  command = plan

  variables {
    create_container_app = false
  }

  assert {
    condition     = module.container_app.container_app_id == null && length(azapi_resource.sign_in) == 0
    error_message = "The app and its sign-in must wait until the first image is in the registry."
  }

  assert {
    condition     = !contains(keys(module.key_vault.secret_ids), "microsoft-provider-authentication-secret")
    error_message = "The Entra client secret cannot exist in Key Vault before the app (and its registration) exist."
  }
}

run "app_is_internal_and_requires_sign_in" {
  command = plan

  variables {
    create_container_app = true
  }

  assert {
    condition     = length(azapi_resource.sign_in) == 1
    error_message = "Entra sign-in must be configured whenever the app exists."
  }

  assert {
    condition     = azapi_resource.sign_in[0].body.properties.globalValidation.unauthenticatedClientAction == "RedirectToLoginPage"
    error_message = "Unauthenticated requests must be sent to the Entra login."
  }
}

run "database_and_storage_are_never_public" {
  command = plan

  assert {
    condition     = module.storage.id != null
    error_message = "Storage account must be created regardless of create_container_app."
  }

  assert {
    condition     = module.postgresql.fqdn != null
    error_message = "PostgreSQL must be created regardless of create_container_app."
  }
}

run "postgresql_ha_needs_non_burstable_sku" {
  command = plan

  variables {
    postgresql_sku_name   = "B_Standard_B1ms"
    postgresql_ha_enabled = true
  }

  expect_failures = [check.postgresql_ha_needs_non_burstable_sku]
}

run "registry_zone_redundancy_needs_premium" {
  command = plan

  variables {
    registry_sku                     = "Basic"
    registry_zone_redundancy_enabled = true
  }

  expect_failures = [var.registry_zone_redundancy_enabled]
}

run "zone_redundancy_warns_with_one_replica" {
  command = plan

  variables {
    zone_redundancy_enabled = true
    min_replicas            = 1
  }

  expect_failures = [check.zone_redundancy_has_replicas_to_spread]
}

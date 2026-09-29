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

  allowed_group_ids     = ["00000000-0000-0000-0000-0000000000bb"]
  postgresql_sku_name   = "B_Standard_B1ms"
  postgresql_ha_enabled = false
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

  assert {
    condition     = module.storage.public_network_access_enabled == false
    error_message = "Storage account must not allow public network access."
  }

  assert {
    condition     = module.storage.shared_access_key_enabled == false
    error_message = "Storage account must not allow access via a shared key, only the app's managed identity."
  }

  assert {
    condition     = module.key_vault.network_acls_default_action == "Deny"
    error_message = "Key Vault must deny public access by default; key_vault_allowed_ip_ranges is the only opt-in."
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

run "postgresql_ha_plans_cleanly_with_a_general_purpose_sku" {
  command = plan

  variables {
    environment             = "uat"
    postgresql_sku_name     = "GP_Standard_D2ds_v5"
    postgresql_ha_enabled   = true
    postgresql_ha_mode      = "ZoneRedundant"
    postgresql_zone         = "1"
    postgresql_standby_zone = "2"
    zone_redundancy_enabled = true
    min_replicas            = 2
  }

  assert {
    condition     = module.postgresql.fqdn != null
    error_message = "A General Purpose SKU with HA and zones must plan cleanly."
  }
}

run "central_private_dns_zones_are_used_instead_of_creating_new_ones" {
  command = plan

  variables {
    postgresql_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
    key_vault_private_dns_zone_id  = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    storage_private_dns_zone_id    = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_dns_zone.postgresql) == 0 && length(azurerm_private_dns_zone.key_vault) == 0 && length(azurerm_private_dns_zone.storage) == 0
    error_message = "When a central zone ID is supplied, this stack must not create its own copy of that zone."
  }
}

run "environment_never_links_privatelink_zones_to_the_hub" {
  command = plan

  variables {
    hub_virtual_network_id = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.postgresql) == 1 && azurerm_private_dns_zone_virtual_network_link.postgresql[0].name == "link-spoke"
    error_message = "The self-created postgresql zone must link only the spoke, never the hub, or two environments sharing a hub collide (a VNet cannot link to two zones with the same name)."
  }
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

# Plans with mocked providers, so no Azure access is needed:
#   terraform test -var-file=../../environments/dev/terraform.tfvars
mock_provider "azurerm" {
  mock_resource "azurerm_container_app" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.App/containerApps/ca-test" }
  }
}
mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-0000000000aa" }
  }
}
mock_provider "azapi" {}
mock_provider "time" {}

run "first_apply_creates_platform_only" {
  command = plan

  variables {
    create_container_app = false
  }

  assert {
    condition     = module.container_app.container_app_id == null && length(azapi_resource.sign_in) == 0
    error_message = "The app and its sign-in must wait until the first image is in the registry."
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

  assert {
    condition     = length(module.entra_app) == 1
    error_message = "The app registration must be created with the app."
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

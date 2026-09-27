terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azapi = {
      # Only for the container app's sign-in settings, which azurerm does not cover.
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Partial configuration: values come from environments/<env>/backend.hcl.
  backend "azurerm" {}
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
  }

  # Partial configuration: values come from environments/<env>/backend.hcl,
  # so each environment can keep its state in its own subscription.
  backend "azurerm" {}
}

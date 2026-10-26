# In-network availability probe for private sites. Internet web tests cannot
# reach a private endpoint, so a scheduled Container Apps job inside the VNet
# requests the site and records the result in Application Insights.
# No code package or storage account: the script is inlined from probe.sh.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name_suffix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  description = "Subnet delegated to Microsoft.App/environments (at least /27)."
  type        = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "application_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "tests" {
  description = "Probe targets keyed by test name: url and expected HTTP status."
  type = map(object({
    url             = string
    expected_status = optional(number, 200)
  }))
}

variable "zone_redundancy_enabled" {
  description = "Spread the probe's Container Apps environment across availability zones. Fixed at creation."
  type        = bool
  default     = false
}

variable "cron_expression" {
  description = "How often to probe (UTC cron)."
  type        = string
  default     = "*/5 * * * *"
}

variable "image" {
  description = "Any image with bash, curl and awk. Mirror it into an APEX registry for a fully private pull."
  type        = string
  default     = "mcr.microsoft.com/azure-cli:latest"
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${var.name_suffix}"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  infrastructure_subnet_id       = var.subnet_id
  internal_load_balancer_enabled = true
  zone_redundancy_enabled        = var.zone_redundancy_enabled
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  tags                           = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app_job" "probe" {
  for_each = var.tests

  name                         = substr("caj-probe-${each.key}-${var.name_suffix}", 0, 32)
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = azurerm_container_app_environment.this.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 120
  replica_retry_limit          = 0
  tags                         = var.tags

  schedule_trigger_config {
    cron_expression          = var.cron_expression
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name  = "ai-connection-string"
    value = var.application_insights_connection_string
  }

  template {
    container {
      name    = "probe"
      image   = var.image
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["/bin/bash", "-c", file("${path.module}/probe.sh")]

      env {
        name  = "TARGET_URL"
        value = each.value.url
      }
      env {
        name  = "EXPECTED_STATUS"
        value = tostring(each.value.expected_status)
      }
      env {
        name  = "TEST_NAME"
        value = each.key
      }
      env {
        name  = "PROBE_LOCATION"
        value = "vnet-${var.location}"
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "ai-connection-string"
      }
    }
  }
}

output "test_names" {
  description = "Availability result names the alerts filter on."
  value       = keys(var.tests)
}

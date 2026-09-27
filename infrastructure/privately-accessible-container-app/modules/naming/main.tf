# Naming convention: <type>-<workload>-<environment>-<region>-<instance>
# Follows the Cloud Adoption Framework abbreviations. Pure computation, no resources.

variable "workload" {
  description = "Short workload code, lowercase letters and digits (e.g. \"pca\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.workload))
    error_message = "workload must be 2-10 lowercase letters or digits, starting with a letter."
  }
}

variable "environment" {
  description = "Environment code: dev, qa, uat or prod."
  type        = string
}

variable "location" {
  description = "Azure region name (e.g. westeurope)."
  type        = string
}

variable "instance" {
  description = "Instance number, three digits."
  type        = string
  default     = "001"
}

locals {
  region_codes = {
    westeurope         = "weu"
    northeurope        = "neu"
    uksouth            = "uks"
    eastus             = "eus"
    eastus2            = "eus2"
    centralus          = "cus"
    westus2            = "wus2"
    eastasia           = "ea"
    southeastasia      = "sea"
    australiaeast      = "aue"
    switzerlandnorth   = "chn"
    germanywestcentral = "gwc"
    francecentral      = "frc"
  }

  region = lookup(local.region_codes, var.location, substr(var.location, 0, 4))
  suffix = "${var.workload}-${var.environment}-${local.region}-${var.instance}"
}

output "suffix" { value = local.suffix }
output "resource_group" { value = "rg-${local.suffix}" }
output "virtual_network" { value = "vnet-${local.suffix}" }
output "subnet_container_apps" { value = "snet-cae-${local.suffix}" }
output "nsg_container_apps" { value = "nsg-cae-${local.suffix}" }
output "container_apps_environment" { value = "cae-${local.suffix}" }
output "container_app" { value = "ca-${local.suffix}" }
output "container_registry" { value = replace("cr${local.suffix}", "-", "") } # alphanumeric only
output "managed_identity" { value = "id-${local.suffix}" }
output "entra_app" { value = "app-${local.suffix}" }
output "log_analytics" { value = "log-${local.suffix}" }
output "application_insights" { value = "appi-${local.suffix}" }
output "action_group" { value = "ag-${local.suffix}" }
output "action_group_short" { value = substr(replace("${var.workload}${var.environment}", "-", ""), 0, 12) }
output "budget" { value = "budget-${local.suffix}" }

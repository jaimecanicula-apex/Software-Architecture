output "resource_group" { value = "rg-${local.suffix}" }

output "static_web_app" { value = "stapp-${local.suffix}" }

output "front_door_profile" { value = "afd-${local.global_suffix}" }

output "front_door_endpoint" { value = "fde-${local.global_suffix}" }

output "waf_policy" { value = replace("waf${local.global_suffix}", "-", "") } # alphanumeric only

output "log_analytics" { value = "log-${local.suffix}" }

output "application_insights" { value = "appi-${local.suffix}" }

output "action_group" { value = "ag-${local.suffix}" }

output "action_group_short" { value = substr(replace("${var.workload}${var.environment}", "-", ""), 0, 12) }

output "budget" { value = "budget-${local.suffix}" }

output "suffix" { value = local.suffix }
output "virtual_network" { value = "vnet-${local.suffix}" }
output "subnet_private_endpoints" { value = "snet-pe-${local.suffix}" }
output "subnet_probe" { value = "snet-probe-${local.suffix}" }
output "nsg_private_endpoints" { value = "nsg-pe-${local.suffix}" }
output "nsg_probe" { value = "nsg-probe-${local.suffix}" }
output "private_link_scope" { value = "ampls-${local.suffix}" }
output "entra_app" { value = "app-${local.suffix}" }
output "private_endpoint_site" { value = "pe-stapp-${local.suffix}" }

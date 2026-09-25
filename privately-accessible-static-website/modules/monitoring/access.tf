# Who can see the monitoring. Scoped to this environment's resource group only.
#   Viewers:   open the workbook, query logs, read metrics and alerts.
#   Operators: viewers + manage alert rules, action groups and workbooks.

locals {
  viewer_roles   = ["Reader", "Monitoring Reader", "Log Analytics Reader"]
  operator_roles = ["Reader", "Monitoring Contributor", "Log Analytics Reader", "Workbook Contributor"]

  role_assignments = merge(
    { for pair in setproduct(var.viewer_principal_ids, local.viewer_roles) : "viewer|${pair[0]}|${pair[1]}" => { principal_id = pair[0], role = pair[1] } },
    { for pair in setproduct(var.operator_principal_ids, local.operator_roles) : "operator|${pair[0]}|${pair[1]}" => { principal_id = pair[0], role = pair[1] } },
  )
}

resource "azurerm_role_assignment" "monitoring" {
  for_each = local.role_assignments

  scope                = var.resource_group_id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  description          = "Monitoring access for the static website (${var.name_suffix})."
}

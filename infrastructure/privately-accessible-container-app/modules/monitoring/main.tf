# Log Analytics (container console and system logs), workspace-based Application
# Insights (requests, exceptions), an Action Group for alerts, and read access
# for the people who need to see them.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "log_analytics_name" {
  type = string
}

variable "application_insights_name" {
  type = string
}

variable "action_group_name" {
  type = string
}

variable "action_group_short_name" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB. -1 means no cap."
  type        = number
  default     = -1
}

variable "alert_email_receivers" {
  type    = list(string)
  default = []
}

variable "viewer_principal_ids" {
  description = "Entra group object IDs that can read logs, metrics and alerts."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = var.application_insights_name
  resource_group_name = var.resource_group_name
  location            = var.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

locals {
  viewer_roles = ["Reader", "Monitoring Reader", "Log Analytics Reader"]
}

resource "azurerm_role_assignment" "viewers" {
  for_each = { for pair in setproduct(var.viewer_principal_ids, local.viewer_roles) : "${pair[0]}|${pair[1]}" => { principal_id = pair[0], role = pair[1] } }

  scope                = var.resource_group_id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}

output "action_group_id" {
  value = azurerm_monitor_action_group.this.id
}

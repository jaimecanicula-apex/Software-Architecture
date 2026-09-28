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

variable "postgresql_server_id" {
  description = "Required: the PostgreSQL server to send diagnostics and CPU alerts for. This stack always has one, so it is not optional (count on a not-yet-known resource ID cannot work — Terraform must know at plan time whether the resource exists)."
  type        = string
}

variable "key_vault_id" {
  description = "Required: the Key Vault to send diagnostics for."
  type        = string
}

variable "storage_account_id" {
  description = "Required: the storage account to send diagnostics and a capacity alert for."
  type        = string
}

variable "postgresql_cpu_alert_threshold" {
  description = "Percent CPU averaged over 15 minutes that triggers the alert."
  type        = number
  default     = 80
}

variable "storage_used_capacity_alert_threshold_gb" {
  description = "Blob storage used capacity, in GB, that triggers the alert."
  type        = number
  default     = 50
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

resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "diag-postgresql"
  target_resource_id         = var.postgresql_server_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-key-vault"
  target_resource_id         = var.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "diag-storage"
  target_resource_id         = var.storage_account_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_metric_alert" "postgresql_cpu" {
  name                = "alert-postgresql-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]
  description         = "PostgreSQL CPU has averaged above the threshold for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.postgresql_cpu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "storage_capacity" {
  name                = "alert-storage-capacity"
  resource_group_name = var.resource_group_name
  scopes              = [var.storage_account_id]
  description         = "Blob storage used capacity passed the threshold."
  severity            = 3
  frequency           = "PT1H"
  window_size         = "PT6H"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "UsedCapacity"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.storage_used_capacity_alert_threshold_gb * 1024 * 1024 * 1024
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
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

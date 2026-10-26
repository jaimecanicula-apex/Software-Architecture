# Shared file library: one private blob container that signed-in users read and
# write with their own Entra identity. No account keys, no public access.
#
# Users get a custom role scoped to the one container: blob read, write and
# delete plus blob tag read, so the page can hide files that malware scanning
# has flagged.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  description = "Storage account name: 3-24 lowercase letters and digits."
  type        = string
}

variable "role_name" {
  type = string
}

variable "private_endpoint_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  description = "privatelink.blob.core.windows.net"
  type        = string
}

variable "replication_type" {
  description = "LRS, ZRS, GZRS or RAGZRS. ZRS in dev/qa, GZRS in uat/prod."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GZRS or RAGZRS."
  }
}

variable "container_name" {
  type    = string
  default = "files"
}

variable "soft_delete_retention_days" {
  description = "Days deleted files, deleted containers and old file versions are kept."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "cors_allowed_origins" {
  description = "Origins the browser calls from: the site's own https host names."
  type        = list(string)
}

variable "user_group_ids" {
  description = "Entra groups whose members can list, upload, download and delete files."
  type        = list(string)
  default     = []
}

variable "malware_scanning_enabled" {
  description = "Defender for Storage malware scanning on upload. Flagged files get a blob index tag that the page hides."
  type        = bool
  default     = false
}

variable "malware_scan_cap_gb_per_month" {
  description = "Stops scanning (and its charge) after this many GB a month. -1 for no cap."
  type        = number
  default     = 1000
}

variable "diagnostics_enabled" {
  description = "Send blob read, write and delete logs to log_analytics_workspace_id. A separate flag because the workspace ID is unknown until it is created, and count cannot depend on it."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_storage_account" "this" {
  name                             = var.name
  resource_group_name              = var.resource_group_name
  location                         = var.location
  account_tier                     = "Standard"
  account_replication_type         = var.replication_type
  min_tls_version                  = "TLS1_2"
  https_traffic_only_enabled       = true
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  public_network_access_enabled    = false
  cross_tenant_replication_enabled = false
  tags                             = var.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    cors_rule {
      allowed_origins    = var.cors_allowed_origins
      allowed_methods    = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS"]
      allowed_headers    = ["authorization", "content-type", "x-ms-*", "if-match", "if-none-match"]
      exposed_headers    = ["x-ms-*", "etag", "content-length", "content-type"]
      max_age_in_seconds = 3600
    }
  }
}

# Old versions are billed as storage, so they are removed after the retention period.
resource "azurerm_storage_management_policy" "versions" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "delete-old-versions"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = var.soft_delete_retention_days
      }
    }
  }
}

resource "azurerm_storage_container" "files" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "this" {
  name                          = var.private_endpoint_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-${var.private_endpoint_name}"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${var.private_endpoint_name}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_definition" "files_user" {
  name        = var.role_name
  scope       = azurerm_storage_account.this.id
  description = "List, read, upload, overwrite and delete blobs, and read blob tags."

  permissions {
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read",
    ]
  }

  assignable_scopes = [azurerm_storage_account.this.id]
}

resource "azurerm_role_assignment" "users" {
  for_each = toset(var.user_group_ids)

  scope              = azurerm_storage_container.files.id
  role_definition_id = azurerm_role_definition.files_user.role_definition_resource_id
  principal_id       = each.value
}

resource "azurerm_security_center_storage_defender" "this" {
  count = var.malware_scanning_enabled ? 1 : 0

  storage_account_id                          = azurerm_storage_account.this.id
  malware_scanning_on_upload_enabled          = true
  malware_scanning_on_upload_cap_gb_per_month = var.malware_scan_cap_gb_per_month
  override_subscription_settings_enabled      = true
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.diagnostics_enabled ? 1 : 0

  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }
}

output "id" {
  value = azurerm_storage_account.this.id
}

output "account_name" {
  value = azurerm_storage_account.this.name
}

output "container_name" {
  value = azurerm_storage_container.files.name
}

output "private_ip_address" {
  value = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

output "public_network_access_enabled" {
  value = azurerm_storage_account.this.public_network_access_enabled
}

output "shared_access_key_enabled" {
  value = azurerm_storage_account.this.shared_access_key_enabled
}

output "malware_scanning_enabled" {
  value = length(azurerm_security_center_storage_defender.this) > 0
}

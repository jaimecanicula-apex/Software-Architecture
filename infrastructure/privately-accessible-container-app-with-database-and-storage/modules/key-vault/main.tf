# Key Vault for generated secrets (DB password, Flask secret key, seed user
# passwords, Entra client secret, App Insights connection string): RBAC
# authorization, private endpoint only. Network ACLs default-deny except the
# IP ranges Terraform itself runs from — needed because Terraform has to
# write these secrets through the data plane before anything else can read
# them, the same "first apply reaches further than the private endpoint
# allows" shape as the registry-is-empty step in the sibling template.

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "purge_protection_enabled" {
  type    = bool
  default = false
}

variable "allowed_ip_ranges" {
  description = "Public IP ranges (CIDR) allowed to reach the vault's data plane during terraform apply, e.g. the pipeline agent's or your own. Empty means only the private endpoint can reach it, so Terraform itself needs network access to the spoke (a self-hosted agent, or a bastion/VPN into it)."
  type        = list(string)
  default     = []
}

variable "writer_principal_id" {
  description = "Object ID of the identity running Terraform. Granted Key Vault Secrets Officer so it can write the generated secrets."
  type        = string
}

variable "reader_principal_id" {
  description = "The container app's managed identity. Granted Key Vault Secrets User."
  type        = string
}

variable "secrets" {
  description = "Secret name => value."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_key_vault" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = var.purge_protection_enabled
  public_network_access_enabled = length(var.allowed_ip_ranges) > 0
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "writer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.writer_principal_id
}

resource "azurerm_role_assignment" "reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.reader_principal_id
}

resource "azurerm_key_vault_secret" "this" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  name         = each.value
  value        = var.secrets[each.value]
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.writer]
}

output "id" {
  value = azurerm_key_vault.this.id
}

output "secret_ids" {
  value = { for name, secret in azurerm_key_vault_secret.this : name => secret.versionless_id }
}

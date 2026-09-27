# Entra ID app registration for the Static Web App's built-in authentication.
# Single tenant (APEX only). With assignment required, only the listed groups
# can sign in; everyone else in the tenant is refused by Entra itself.

terraform {
  required_providers {
    azuread = {
      source = "hashicorp/azuread"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

variable "display_name" {
  type = string
}

variable "site_host_name" {
  description = "Host name users reach the site on (default or custom)."
  type        = string
}

variable "allowed_group_ids" {
  description = "Entra group object IDs allowed to sign in. Empty with assignment_required = false lets any APEX account in."
  type        = list(string)
  default     = []
}

variable "assignment_required" {
  type    = bool
  default = true
}

variable "owners" {
  description = "Object IDs that own the app registration (the deploying identity is always added)."
  type        = list(string)
  default     = []
}

variable "secret_rotation_days" {
  type    = number
  default = 180
}

data "azuread_client_config" "current" {}

resource "azuread_application" "this" {
  display_name     = var.display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = distinct(concat([data.azuread_client_config.current.object_id], var.owners))

  web {
    implicit_grant {
      id_token_issuance_enabled = true
    }
  }

  # Redirect URIs are managed by azuread_application_redirect_uris below.
  lifecycle {
    ignore_changes = [web[0].redirect_uris]
  }
}

resource "azuread_application_redirect_uris" "this" {
  application_id = azuread_application.this.id
  type           = "Web"
  redirect_uris  = ["https://${var.site_host_name}/.auth/login/aad/callback"]
}

resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = var.assignment_required
  owners                       = distinct(concat([data.azuread_client_config.current.object_id], var.owners))
}

resource "time_rotating" "secret" {
  rotation_days = var.secret_rotation_days
}

resource "azuread_application_password" "this" {
  application_id      = azuread_application.this.id
  display_name        = "static-web-app-auth"
  end_date            = timeadd(time_rotating.secret.id, "${var.secret_rotation_days * 24 + 720}h")
  rotate_when_changed = { rotation = time_rotating.secret.id }
}

# Default access role: lets the listed groups sign in.
resource "azuread_app_role_assignment" "groups" {
  for_each = toset(var.allowed_group_ids)

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.this.object_id
}

output "client_id" {
  value = azuread_application.this.client_id
}

output "client_secret" {
  value     = azuread_application_password.this.value
  sensitive = true
}

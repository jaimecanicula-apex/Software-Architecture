# Approved external users: a security group for the site, B2B invitations for
# the people listed, and their membership of that group. Only this group (plus
# any existing groups passed to the stack) is assigned to the app, so anyone
# not approved is refused at sign-in.

terraform {
  required_providers {
    azuread = {
      source = "hashicorp/azuread"
    }
  }
}

variable "group_name" {
  type = string
}

variable "group_owners" {
  description = "Object IDs allowed to manage the group (the deploying identity is always added)."
  type        = list(string)
  default     = []
}

variable "guest_emails" {
  description = "External people to invite as B2B guests and approve for the site. Keep this list short; for many users, manage the group in Entra instead."
  type        = list(string)
  default     = []
}

variable "redirect_url" {
  description = "Where invited guests land after accepting the invitation."
  type        = string
}

variable "invitation_message" {
  type    = string
  default = "You have been given access to a website. Accept this invitation to sign in."
}

data "azuread_client_config" "current" {}

resource "azuread_group" "site_users" {
  display_name     = var.group_name
  description      = "People approved to sign in to the public sign-in static website."
  security_enabled = true
  owners           = distinct(concat([data.azuread_client_config.current.object_id], var.group_owners))
}

resource "azuread_invitation" "guest" {
  for_each = toset(var.guest_emails)

  user_email_address = each.value
  redirect_url       = var.redirect_url

  message {
    body = var.invitation_message
  }
}

resource "azuread_group_member" "guest" {
  for_each = azuread_invitation.guest

  group_object_id  = azuread_group.site_users.object_id
  member_object_id = each.value.user_id
}

output "group_id" {
  value = azuread_group.site_users.object_id
}

output "redeem_urls" {
  description = "Invitation links, in case the email does not arrive."
  value       = { for k, v in azuread_invitation.guest : k => v.redeem_url }
  sensitive   = true
}

output "invited_user_ids" {
  value = { for k, v in azuread_invitation.guest : k => v.user_id }
}

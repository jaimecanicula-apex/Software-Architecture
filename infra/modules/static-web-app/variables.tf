variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  description = "Static Web Apps is only offered in a few regions."
  type        = string

  validation {
    condition     = contains(["westus2", "centralus", "eastus2", "westeurope", "eastasia"], var.location)
    error_message = "Static Web Apps supports westus2, centralus, eastus2, westeurope and eastasia."
  }
}

variable "sku" {
  description = "Free or Standard. Standard is required to lock the origin to Front Door."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard"], var.sku)
    error_message = "sku must be Free or Standard."
  }
}

variable "preview_environments_enabled" {
  description = "Allow pull-request preview environments."
  type        = bool
  default     = true
}

variable "app_settings" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

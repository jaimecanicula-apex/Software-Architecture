variable "profile_name" {
  type = string
}

variable "endpoint_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "sku_name" {
  description = "Standard_AzureFrontDoor or Premium_AzureFrontDoor. Premium is required for WAF managed rule sets."
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku_name)
    error_message = "sku_name must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "origin_host_name" {
  description = "Default host name of the Static Web App."
  type        = string
}

variable "custom_domains" {
  description = "Custom domains keyed by a short name. Set dns_zone_id only when the zone is in Azure DNS; otherwise publish the validation TXT record at the external registrar."
  type = map(object({
    host_name   = string
    dns_zone_id = optional(string)
  }))
  default = {}
}

variable "health_probe_path" {
  type    = string
  default = "/"
}

variable "health_probe_interval_seconds" {
  type    = number
  default = 100
}

variable "caching_enabled" {
  description = "Cache static content at the edge and compress text assets."
  type        = bool
  default     = true
}

variable "security_headers" {
  description = "Response headers set at the edge (max 5, one Front Door rule). Content-Security-Policy belongs in staticwebapp.config.json."
  type        = map(string)
  default = {
    "Strict-Transport-Security" = "max-age=31536000; includeSubDomains"
    "X-Content-Type-Options"    = "nosniff"
    "Referrer-Policy"           = "strict-origin-when-cross-origin"
    "Permissions-Policy"        = "camera=(), microphone=(), geolocation=()"
    "X-Frame-Options"           = "DENY"
  }

  validation {
    condition     = length(var.security_headers) <= 5
    error_message = "A Front Door rule supports at most 5 actions; keep security_headers to 5 entries."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

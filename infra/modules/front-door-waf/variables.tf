variable "name" {
  description = "WAF policy name, letters and digits only."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,127}$", var.name))
    error_message = "WAF policy names must start with a letter and contain only letters and digits."
  }
}

variable "resource_group_name" {
  type = string
}

variable "sku_name" {
  description = "Must match the Front Door profile SKU."
  type        = string
}

variable "front_door_profile_id" {
  type = string
}

variable "domain_ids" {
  description = "Front Door endpoint and custom domain IDs protected by this policy."
  type        = list(string)
}

variable "mode" {
  description = "Detection logs only; Prevention blocks. Start in Detection, tune, then switch."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.mode)
    error_message = "mode must be Detection or Prevention."
  }
}

variable "rate_limit_per_minute" {
  description = "Requests per client IP per minute before blocking."
  type        = number
  default     = 1000
}

variable "blocked_country_codes" {
  description = "ISO 3166-1 alpha-2 country codes to block. Empty disables the rule."
  type        = list(string)
  default     = []
}

variable "managed_rule_sets" {
  description = "Managed rule sets, applied on Premium only."
  type = list(object({
    type    = string
    version = string
    action  = string
  }))
  default = [
    { type = "Microsoft_DefaultRuleSet", version = "2.1", action = "Block" },
    { type = "Microsoft_BotManagerRuleSet", version = "1.1", action = "Block" },
  ]
}

variable "tags" {
  type    = map(string)
  default = {}
}

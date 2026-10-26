variable "workload" {
  description = "Short workload code, lowercase letters and digits (e.g. \"sws\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.workload))
    error_message = "workload must be 2-10 lowercase letters or digits, starting with a letter."
  }
}

variable "environment" {
  description = "Environment code: dev, qa, uat or prod."
  type        = string
}

variable "location" {
  description = "Azure region name (e.g. westeurope)."
  type        = string
}

variable "instance" {
  description = "Instance number, three digits."
  type        = string
  default     = "001"
}

variable "unique_seed" {
  description = "Any stable value (the subscription ID) hashed into the storage account name, which must be unique across all of Azure."
  type        = string
  default     = ""
}

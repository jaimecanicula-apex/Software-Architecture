# Naming convention: <type>-<workload>-<environment>-<region>-<instance>
# Follows the Cloud Adoption Framework abbreviations. Pure computation, no resources.

locals {
  region_codes = {
    westeurope         = "weu"
    northeurope        = "neu"
    uksouth            = "uks"
    eastus             = "eus"
    eastus2            = "eus2"
    centralus          = "cus"
    westus2            = "wus2"
    eastasia           = "ea"
    southeastasia      = "sea"
    australiaeast      = "aue"
    switzerlandnorth   = "chn"
    germanywestcentral = "gwc"
    francecentral      = "frc"
  }

  region = lookup(local.region_codes, var.location, substr(var.location, 0, 4))
  suffix = "${var.workload}-${var.environment}-${local.region}-${var.instance}"
  # Front Door and its WAF policy are global resources, so the region is left out.
  global_suffix = "${var.workload}-${var.environment}-${var.instance}"
}

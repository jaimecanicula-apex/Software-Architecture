# Remote state for UAT. Created by public-signin-static-website/bootstrap.
# The state can live in a different subscription from the resources.
subscription_id      = "00000000-0000-0000-0000-000000000003" # <state subscription id>
resource_group_name  = "rg-tfstate-uat"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "public-signin-static-website/uat.tfstate"
use_azuread_auth     = true

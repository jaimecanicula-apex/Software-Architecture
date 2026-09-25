# Remote state for DEV. Created by public-signin-static-website/bootstrap.
# The state can live in a different subscription from the resources.
subscription_id      = "00000000-0000-0000-0000-000000000001" # <state subscription id>
resource_group_name  = "rg-tfstate-dev"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "public-signin-static-website/dev.tfstate"
use_azuread_auth     = true

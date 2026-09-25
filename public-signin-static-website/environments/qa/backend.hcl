# Remote state for QA. Created by public-signin-static-website/bootstrap.
# The state can live in a different subscription from the resources.
subscription_id      = "00000000-0000-0000-0000-000000000002" # <state subscription id>
resource_group_name  = "rg-tfstate-qa"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "public-signin-static-website/qa.tfstate"
use_azuread_auth     = true

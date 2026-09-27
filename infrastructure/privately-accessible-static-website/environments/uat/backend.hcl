# Remote state for UAT. Created by infrastructure/privately-accessible-static-website/bootstrap.
subscription_id      = "00000000-0000-0000-0000-000000000013" # <state subscription id>
resource_group_name  = "rg-tfstate-uat"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "private-static-website/uat.tfstate"
use_azuread_auth     = true

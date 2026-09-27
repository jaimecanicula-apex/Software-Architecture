# Remote state for DEV. Created by infrastructure/privately-accessible-static-website/bootstrap.
subscription_id      = "00000000-0000-0000-0000-000000000011" # <state subscription id>
resource_group_name  = "rg-tfstate-dev"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "private-static-website/dev.tfstate"
use_azuread_auth     = true

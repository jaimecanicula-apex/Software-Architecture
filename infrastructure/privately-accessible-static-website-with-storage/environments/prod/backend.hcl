# Remote state for PROD. Created by infrastructure/privately-accessible-static-website-with-storage/bootstrap.
subscription_id      = "00000000-0000-0000-0000-000000000014" # <state subscription id>
resource_group_name  = "rg-tfstate-prod"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "private-static-website-with-storage/prod.tfstate"
use_azuread_auth     = true

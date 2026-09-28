# Remote state for DEV. Created by infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap.
subscription_id      = "00000000-0000-0000-0000-000000000001" # <state subscription id>
resource_group_name  = "rg-tfstate-dev"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "private-container-app-with-db/dev.tfstate"
use_azuread_auth     = true

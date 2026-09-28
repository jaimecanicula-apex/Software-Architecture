# Remote state for QA. Created by infrastructure/privately-accessible-container-app-with-database-and-storage/bootstrap.
subscription_id      = "00000000-0000-0000-0000-000000000002" # <state subscription id>
resource_group_name  = "rg-tfstate-qa"
storage_account_name = "<tfstate storage account>"
container_name       = "tfstate"
key                  = "private-container-app-with-db/qa.tfstate"
use_azuread_auth     = true

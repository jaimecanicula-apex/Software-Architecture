subscription_id      = "00000000-0000-0000-0000-000000000004" # <state subscription id>
location             = "westeurope"
resource_group_name  = "rg-tfstate-prod"
storage_account_name = "sttfstateprod001"
replication_type     = "GZRS" # zone- and geo-redundant; ZRS keeps state in one region

state_writer_principal_ids = [
  # "<object id of the pipeline service principal or managed identity>",
]

tags = {
  "managed-by" = "terraform"
  purpose      = "terraform-state"
}

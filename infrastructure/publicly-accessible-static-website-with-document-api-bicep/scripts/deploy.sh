#!/usr/bin/env bash
# Deploy one environment of the Bicep template.
#   ./publicly-accessible-static-website-with-document-api-bicep/scripts/deploy.sh <dev|qa|uat|prod> <what-if|deploy|show|delete>
#
# deploy does three things, in this order:
#   1. checks the settings Bicep cannot cross-check (zones need zone-redundant storage)
#   2. deploys main.bicep as a deployment stack, so resources removed from the template are
#      removed from Azure (the stack plays the role of Terraform state)
#   3. approves Front Door's Private Link connection on the Function App, without which /api/*
#      returns 5xx, and prints what to do next
#
# Needs: az login, and rights to deploy at subscription scope and approve private endpoint connections.
set -euo pipefail

env="${1:?usage: deploy.sh <dev|qa|uat|prod> <what-if|deploy|show|delete>}"
cmd="${2:-what-if}"
root="$(cd "$(dirname "$0")/.." && pwd)"
params="$root/environments/$env/main.bicepparam"
settings="$root/environments/$env/deployment.env"
[ -f "$params" ] || { echo "No such environment: $env" >&2; exit 1; }

# deployment.env: SUBSCRIPTION_ID, TENANT_ID, PUBLISHER_GROUP_IDS
set -a
# shellcheck disable=SC1090
. "$settings"
set +a
export PUBLISHER_GROUP_IDS

param() { sed -n "s/^param $1 = '\\(.*\\)'.*/\\1/p" "$params" | head -1; }
flag() { sed -n "s/^param $1 = \\(true\\|false\\).*/\\1/p" "$params" | head -1; }
workload="$(param workload)"
location="$(param location)"
stack="stack-$workload-$env"

az account set --subscription "$SUBSCRIPTION_ID"
current_tenant="$(az account show --query tenantId -o tsv)"
[ "$current_tenant" = "$TENANT_ID" ] || { echo "Signed in to tenant $current_tenant, expected $TENANT_ID." >&2; exit 1; }

preflight() {
  # Zone-redundant compute with locally redundant storage would lose the zone resilience it paid for.
  if [ "$(flag zoneRedundancyEnabled)" = "true" ] && [ "$(param storageReplicationType)" = "LRS" ]; then
    echo "zoneRedundancyEnabled is true but storageReplicationType is LRS: use ZRS, GZRS or RAGZRS." >&2
    exit 1
  fi
  # Overlapping subnets are rejected by Azure; catch the common typo (same prefix twice) early.
  if [ "$(param integrationSubnetPrefix)" = "$(param privateEndpointSubnetPrefix)" ]; then
    echo "integrationSubnetPrefix and privateEndpointSubnetPrefix must differ." >&2
    exit 1
  fi
}

case "$cmd" in
  show)
    az stack sub show --name "$stack" --query outputs -o json
    ;;

  delete)
    az stack sub delete --name "$stack" --action-on-unmanage deleteAll --yes
    echo "Removed $stack."
    ;;

  what-if)
    preflight
    az deployment sub what-if --location "$location" --template-file "$root/main.bicep" --parameters "$params"
    ;;

  deploy)
    preflight
    # uat and prod refuse deletes from outside the stack, like their delete lock.
    deny=none
    case "$env" in uat|prod) deny=denyDelete ;; esac
    az stack sub create --name "$stack" --location "$location" \
      --template-file "$root/main.bicep" --parameters "$params" \
      --action-on-unmanage deleteAll --deny-settings-mode "$deny" --yes

    out() { az stack sub show --name "$stack" --query "outputs.$1.value" -o tsv; }
    rg="$(out resourceGroupName)"
    func="$(out functionAppName)"
    swa="$(out staticWebAppName)"
    url="$(out publicUrl)"

    # Front Door asks for Private Link access to the Function; approve it so /api/* works.
    func_id="$(az functionapp show --name "$func" --resource-group "$rg" --query id -o tsv)"
    for conn in $(az network private-endpoint-connection list --id "$func_id" \
        --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv); do
      az network private-endpoint-connection approve --id "$conn" \
        --description "Front Door private access to the Function App" > /dev/null
      echo "Approved Private Link connection ${conn##*/}"
    done

    cat <<EOF

Deployed $env. Next:
  1. Store the pipeline secrets:
       AZURE_STATIC_WEB_APPS_API_TOKEN = az staticwebapp secrets list --name $swa --resource-group $rg --query properties.apiKey -o tsv
       SWA_CONFIG_JSON                 = ./deploy.sh $env show   -> outputs.staticWebAppConfigJson.value
     (it holds the Front Door ID, so the Static Web App accepts only this Front Door)
  2. Deploy the Function package over its private endpoint from the corporate network:
       $func in resource group $rg
  3. Custom domains: add the DNS records from outputs.customDomainValidation, then a CNAME to the Front Door endpoint.
  4. Publishers upload PDFs with metadata approved=true to container '$(out containerName)' on '$(out storageAccountName)'.
  5. Public URL: $url
EOF
    ;;

  *)
    echo "Unknown command: $cmd (use what-if, deploy, show or delete)" >&2
    exit 1
    ;;
esac

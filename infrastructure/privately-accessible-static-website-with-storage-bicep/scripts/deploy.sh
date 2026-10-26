#!/usr/bin/env bash
# Deploy one environment of the Bicep template.
#   ./privately-accessible-static-website-with-storage-bicep/scripts/deploy.sh <dev|qa|uat|prod> <what-if|deploy|show|delete>
#
# deploy does three things, in this order:
#   1. creates or updates the Entra app registration and a fresh client secret
#      (Bicep cannot create secrets), and assigns the allowed groups
#   2. deploys main.bicep as a deployment stack, so resources removed from the
#      template are removed from Azure (the stack plays the role of Terraform state)
#   3. sets the app registration's redirect URIs, which need the site's host name
#
# Needs: az login, and Entra rights to create app registrations and assign groups.
set -euo pipefail

env="${1:?usage: deploy.sh <dev|qa|uat|prod> <what-if|deploy|show|delete>}"
cmd="${2:-what-if}"
root="$(cd "$(dirname "$0")/.." && pwd)"
params="$root/environments/$env/main.bicepparam"
settings="$root/environments/$env/deployment.env"
[ -f "$params" ] || { echo "No such environment: $env" >&2; exit 1; }

# deployment.env: SUBSCRIPTION_ID, TENANT_ID, ALLOWED_GROUP_IDS
set -a
# shellcheck disable=SC1090
. "$settings"
set +a
export ALLOWED_GROUP_IDS

param() { sed -n "s/^param $1 = '\\(.*\\)'.*/\\1/p" "$params" | head -1; }
workload="$(param workload)"
instance="$(param instance)"
location="$(param location)"
stack="stack-$workload-$env"
app_name="app-$workload-$env-$instance"
storage_api="e406a681-f3d4-42a8-90b6-c2b029497af1"   # Azure Storage
storage_scope="03e0da56-190b-40ad-a80c-ea378c433f7f" # user_impersonation

az account set --subscription "$SUBSCRIPTION_ID"
current_tenant="$(az account show --query tenantId -o tsv)"
[ "$current_tenant" = "$TENANT_ID" ] || { echo "Signed in to tenant $current_tenant, expected $TENANT_ID." >&2; exit 1; }

app_id() { az ad app list --display-name "$app_name" --query "[0].appId" -o tsv; }

case "$cmd" in
  show)
    az stack sub show --name "$stack" --query outputs -o json
    ;;

  delete)
    az stack sub delete --name "$stack" --action-on-unmanage deleteAll --yes
    echo "Removed $stack. The app registration '$app_name' is left in Entra; delete it by hand if it is no longer needed."
    ;;

  what-if)
    # No secret is created for a what-if: placeholders stand in for the app's values.
    ENTRA_CLIENT_ID="$(app_id)"
    export ENTRA_CLIENT_ID="${ENTRA_CLIENT_ID:-00000000-0000-0000-0000-000000000000}"
    export ENTRA_CLIENT_SECRET="what-if-placeholder"
    az deployment sub what-if --location "$location" --template-file "$root/main.bicep" --parameters "$params"
    ;;

  deploy)
    # 1. Entra app registration (single tenant, assignment required), secret and groups.
    app="$(app_id)"
    if [ -z "$app" ]; then
      echo "Creating app registration $app_name"
      app="$(az ad app create --display-name "$app_name" --sign-in-audience AzureADMyOrg \
        --enable-id-token-issuance true \
        --required-resource-accesses "[{\"resourceAppId\":\"$storage_api\",\"resourceAccess\":[{\"id\":\"$storage_scope\",\"type\":\"Scope\"}]}]" \
        --query appId -o tsv)"
    fi
    sp="$(az ad sp list --filter "appId eq '$app'" --query "[0].id" -o tsv)"
    [ -n "$sp" ] || sp="$(az ad sp create --id "$app" --query id -o tsv)"
    az ad sp update --id "$sp" --set appRoleAssignmentRequired=true

    # A fresh secret on every deploy replaces the old one; the Static Web App's setting is updated in step 2.
    ENTRA_CLIENT_SECRET="$(az ad app credential reset --id "$app" --display-name static-web-app-auth --years 1 --query password -o tsv)"
    export ENTRA_CLIENT_ID="$app" ENTRA_CLIENT_SECRET

    if [ -n "${ALLOWED_GROUP_IDS:-}" ]; then
      for group in ${ALLOWED_GROUP_IDS//,/ }; do
        az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$sp/appRoleAssignedTo" \
          --body "{\"principalId\":\"$group\",\"resourceId\":\"$sp\",\"appRoleId\":\"00000000-0000-0000-0000-000000000000\"}" \
          > /dev/null 2>&1 || echo "Group $group: already assigned, or you lack the right to assign it."
      done
    fi

    # 2. The deployment stack. uat and prod refuse deletes from outside the stack, like their delete lock.
    deny=none
    case "$env" in uat|prod) deny=denyDelete ;; esac
    az stack sub create --name "$stack" --location "$location" \
      --template-file "$root/main.bicep" --parameters "$params" \
      --action-on-unmanage deleteAll --deny-settings-mode "$deny" --yes

    # 3. Redirect URIs, now that the site's host name exists.
    host="$(az stack sub show --name "$stack" --query "outputs.staticWebAppHostName.value" -o tsv)"
    az ad app update --id "$app" \
      --web-redirect-uris "https://$host/.auth/login/aad/callback" \
      --set "spa.redirectUris=[\"https://$host/files.html\"]"

    swa="$(az stack sub show --name "$stack" --query "outputs.staticWebAppName.value" -o tsv)"
    rg="$(az stack sub show --name "$stack" --query "outputs.resourceGroupName.value" -o tsv)"
    cat <<EOF

Deployed $env. Next:
  1. Grant admin consent once for the Azure Storage permission:
       az ad app permission admin-consent --id $app
  2. Store the pipeline secrets:
       AZURE_STATIC_WEB_APPS_API_TOKEN_INTERNAL_FILES = az staticwebapp secrets list --name $swa --resource-group $rg --query properties.apiKey -o tsv
       SWA_CONFIG_JSON   = ./deploy.sh $env show   -> outputs.staticWebAppConfigJson.value
       FILES_CONFIG_JSON = ./deploy.sh $env show   -> outputs.filesConfigJson.value
  3. Private URL: https://$host/ (reachable only from the APEX network)
EOF
    ;;

  *)
    echo "Unknown command: $cmd (use what-if, deploy, show or delete)" >&2
    exit 1
    ;;
esac

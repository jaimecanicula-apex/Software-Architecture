<#
.SYNOPSIS
Deploy one environment of the Bicep template.
  ./privately-accessible-static-website-with-storage-bicep/scripts/deploy.ps1 -Environment dev -Command what-if

.DESCRIPTION
deploy does three things, in this order:
  1. creates or updates the Entra app registration and a fresh client secret
     (Bicep cannot create secrets), and assigns the allowed groups
  2. deploys main.bicep as a deployment stack, so resources removed from the
     template are removed from Azure (the stack plays the role of Terraform state)
  3. sets the app registration's redirect URIs, which need the site's host name
Needs: az login, and Entra rights to create app registrations and assign groups.
#>
param(
    [Parameter(Mandatory)][ValidateSet('dev', 'qa', 'uat', 'prod')][string]$Environment,
    [ValidateSet('what-if', 'deploy', 'show', 'delete')][string]$Command = 'what-if'
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$params = Join-Path $root "environments/$Environment/main.bicepparam"
$settingsFile = Join-Path $root "environments/$Environment/deployment.env"
if (-not (Test-Path $params)) { throw "No such environment: $Environment" }

# deployment.env: SUBSCRIPTION_ID, TENANT_ID, ALLOWED_GROUP_IDS
$settings = @{}
foreach ($line in Get-Content $settingsFile) {
    $line = ($line -replace '\s+#.*$', '').Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $key, $value = $line -split '=', 2
        $settings[$key.Trim()] = $value.Trim()
    }
}
$env:ALLOWED_GROUP_IDS = $settings['ALLOWED_GROUP_IDS']

function Get-Param([string]$Name) {
    ((Get-Content $params) | Select-String -Pattern "^param $Name = '(.*?)'" | Select-Object -First 1).Matches[0].Groups[1].Value
}
$workload = Get-Param 'workload'
$instance = Get-Param 'instance'
$location = Get-Param 'location'
$stack = "stack-$workload-$Environment"
$appName = "app-$workload-$Environment-$instance"
$storageApi = 'e406a681-f3d4-42a8-90b6-c2b029497af1'   # Azure Storage
$storageScope = '03e0da56-190b-40ad-a80c-ea378c433f7f' # user_impersonation

az account set --subscription $settings['SUBSCRIPTION_ID']
$currentTenant = az account show --query tenantId -o tsv
if ($currentTenant -ne $settings['TENANT_ID']) { throw "Signed in to tenant $currentTenant, expected $($settings['TENANT_ID'])." }

function Get-AppId { az ad app list --display-name $appName --query '[0].appId' -o tsv }

switch ($Command) {
    'show' { az stack sub show --name $stack --query outputs -o json }

    'delete' {
        az stack sub delete --name $stack --action-on-unmanage deleteAll --yes
        Write-Host "Removed $stack. The app registration '$appName' is left in Entra; delete it by hand if it is no longer needed."
    }

    'what-if' {
        # No secret is created for a what-if: placeholders stand in for the app's values.
        $app = Get-AppId
        $env:ENTRA_CLIENT_ID = if ($app) { $app } else { '00000000-0000-0000-0000-000000000000' }
        $env:ENTRA_CLIENT_SECRET = 'what-if-placeholder'
        az deployment sub what-if --location $location --template-file (Join-Path $root 'main.bicep') --parameters $params
    }

    'deploy' {
        # 1. Entra app registration (single tenant, assignment required), secret and groups.
        $app = Get-AppId
        if (-not $app) {
            Write-Host "Creating app registration $appName"
            $access = @(@{ resourceAppId = $storageApi; resourceAccess = @(@{ id = $storageScope; type = 'Scope' }) }) | ConvertTo-Json -Depth 5 -Compress
            $accessFile = New-TemporaryFile
            Set-Content -Path $accessFile -Value $access
            $app = az ad app create --display-name $appName --sign-in-audience AzureADMyOrg --enable-id-token-issuance true `
                --required-resource-accesses "@$accessFile" --query appId -o tsv
            Remove-Item $accessFile
        }
        $sp = az ad sp list --filter "appId eq '$app'" --query '[0].id' -o tsv
        if (-not $sp) { $sp = az ad sp create --id $app --query id -o tsv }
        az ad sp update --id $sp --set appRoleAssignmentRequired=true

        # A fresh secret on every deploy replaces the old one; the Static Web App's setting is updated in step 2.
        $env:ENTRA_CLIENT_ID = $app
        $env:ENTRA_CLIENT_SECRET = az ad app credential reset --id $app --display-name static-web-app-auth --years 1 --query password -o tsv

        foreach ($group in ($settings['ALLOWED_GROUP_IDS'] -split ',' | Where-Object { $_ })) {
            $body = @{ principalId = $group; resourceId = $sp; appRoleId = '00000000-0000-0000-0000-000000000000' } | ConvertTo-Json -Compress
            $bodyFile = New-TemporaryFile
            Set-Content -Path $bodyFile -Value $body
            az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$sp/appRoleAssignedTo" --body "@$bodyFile" *> $null
            if ($LASTEXITCODE -ne 0) { Write-Host "Group ${group}: already assigned, or you lack the right to assign it." }
            Remove-Item $bodyFile
        }

        # 2. The deployment stack. uat and prod refuse deletes from outside the stack, like their delete lock.
        $deny = if ($Environment -in 'uat', 'prod') { 'denyDelete' } else { 'none' }
        az stack sub create --name $stack --location $location `
            --template-file (Join-Path $root 'main.bicep') --parameters $params `
            --action-on-unmanage deleteAll --deny-settings-mode $deny --yes

        # 3. Redirect URIs, now that the site's host name exists.
        $hostName = az stack sub show --name $stack --query 'outputs.staticWebAppHostName.value' -o tsv
        az ad app update --id $app --web-redirect-uris "https://$hostName/.auth/login/aad/callback" `
            --set "spa.redirectUris=[`"https://$hostName/files.html`"]"

        $swa = az stack sub show --name $stack --query 'outputs.staticWebAppName.value' -o tsv
        $rg = az stack sub show --name $stack --query 'outputs.resourceGroupName.value' -o tsv
        Write-Host @"

Deployed $Environment. Next:
  1. Grant admin consent once for the Azure Storage permission:
       az ad app permission admin-consent --id $app
  2. Store the pipeline secrets:
       AZURE_STATIC_WEB_APPS_API_TOKEN_INTERNAL_FILES = az staticwebapp secrets list --name $swa --resource-group $rg --query properties.apiKey -o tsv
       SWA_CONFIG_JSON   = ./deploy.ps1 -Environment $Environment -Command show -> outputs.staticWebAppConfigJson.value
       FILES_CONFIG_JSON = ./deploy.ps1 -Environment $Environment -Command show -> outputs.filesConfigJson.value
  3. Private URL: https://$hostName/ (reachable only from the APEX network)
"@
    }
}

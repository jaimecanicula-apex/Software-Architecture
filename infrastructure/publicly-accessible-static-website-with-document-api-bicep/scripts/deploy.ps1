<#
.SYNOPSIS
Deploy one environment of the Bicep template.
  ./publicly-accessible-static-website-with-document-api-bicep/scripts/deploy.ps1 -Environment dev -Command what-if

.DESCRIPTION
deploy does three things, in this order:
  1. checks the settings Bicep cannot cross-check (zones need zone-redundant storage)
  2. deploys main.bicep as a deployment stack, so resources removed from the template are
     removed from Azure (the stack plays the role of Terraform state)
  3. approves Front Door's Private Link connection on the Function App, without which /api/*
     returns 5xx, and prints what to do next
Needs: az login, and rights to deploy at subscription scope and approve private endpoint connections.
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

# deployment.env: SUBSCRIPTION_ID, TENANT_ID, PUBLISHER_GROUP_IDS
$settings = @{}
foreach ($line in Get-Content $settingsFile) {
    $line = ($line -replace '\s+#.*$', '').Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $key, $value = $line -split '=', 2
        $settings[$key.Trim()] = $value.Trim()
    }
}
$env:PUBLISHER_GROUP_IDS = $settings['PUBLISHER_GROUP_IDS']

function Get-Param([string]$Name) {
    $match = (Get-Content $params) | Select-String -Pattern "^param $Name = '(.*?)'" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value }
}
function Get-Flag([string]$Name) {
    $match = (Get-Content $params) | Select-String -Pattern "^param $Name = (true|false)" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value }
}
$workload = Get-Param 'workload'
$location = Get-Param 'location'
$stack = "stack-$workload-$Environment"

az account set --subscription $settings['SUBSCRIPTION_ID']
$currentTenant = az account show --query tenantId -o tsv
if ($currentTenant -ne $settings['TENANT_ID']) {
    throw "Signed in to tenant $currentTenant, expected $($settings['TENANT_ID'])."
}

function Test-Settings {
    # Zone-redundant compute with locally redundant storage would lose the zone resilience it paid for.
    if ((Get-Flag 'zoneRedundancyEnabled') -eq 'true' -and (Get-Param 'storageReplicationType') -eq 'LRS') {
        throw 'zoneRedundancyEnabled is true but storageReplicationType is LRS: use ZRS, GZRS or RAGZRS.'
    }
    # Overlapping subnets are rejected by Azure; catch the common typo (same prefix twice) early.
    if ((Get-Param 'integrationSubnetPrefix') -eq (Get-Param 'privateEndpointSubnetPrefix')) {
        throw 'integrationSubnetPrefix and privateEndpointSubnetPrefix must differ.'
    }
}
function Get-StackOutput([string]$Name) {
    az stack sub show --name $stack --query "outputs.$Name.value" -o tsv
}

switch ($Command) {
    'show' {
        az stack sub show --name $stack --query outputs -o json
    }
    'delete' {
        az stack sub delete --name $stack --action-on-unmanage deleteAll --yes
        Write-Host "Removed $stack."
    }
    'what-if' {
        Test-Settings
        az deployment sub what-if --location $location --template-file "$root/main.bicep" --parameters $params
    }
    'deploy' {
        Test-Settings
        # uat and prod refuse deletes from outside the stack, like their delete lock.
        $deny = if ($Environment -in 'uat', 'prod') { 'denyDelete' } else { 'none' }
        az stack sub create --name $stack --location $location `
            --template-file "$root/main.bicep" --parameters $params `
            --action-on-unmanage deleteAll --deny-settings-mode $deny --yes

        $rg = Get-StackOutput 'resourceGroupName'
        $func = Get-StackOutput 'functionAppName'
        $swa = Get-StackOutput 'staticWebAppName'
        $url = Get-StackOutput 'publicUrl'

        # Front Door asks for Private Link access to the Function; approve it so /api/* works.
        $funcId = az functionapp show --name $func --resource-group $rg --query id -o tsv
        $pending = az network private-endpoint-connection list --id $funcId `
            --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv
        foreach ($conn in $pending) {
            if ($conn) {
                az network private-endpoint-connection approve --id $conn `
                    --description 'Front Door private access to the Function App' | Out-Null
                Write-Host "Approved Private Link connection $($conn.Split('/')[-1])"
            }
        }

        $container = Get-StackOutput 'containerName'
        $storage = Get-StackOutput 'storageAccountName'
        Write-Host @"

Deployed $Environment. Next:
  1. Store the pipeline secrets:
       AZURE_STATIC_WEB_APPS_API_TOKEN = az staticwebapp secrets list --name $swa --resource-group $rg --query properties.apiKey -o tsv
       SWA_CONFIG_JSON                 = ./deploy.ps1 -Environment $Environment -Command show   -> outputs.staticWebAppConfigJson.value
     (it holds the Front Door ID, so the Static Web App accepts only this Front Door)
  2. Deploy the Function package over its private endpoint from the corporate network:
       $func in resource group $rg
  3. Custom domains: add the DNS records from outputs.customDomainValidation, then a CNAME to the Front Door endpoint.
  4. Publishers upload PDFs with metadata approved=true to container '$container' on '$storage'.
  5. Public URL: $url
"@
    }
}

// Publicly accessible static website with a document API, for anyone on the internet.
//
//   Browser --HTTPS--> Front Door Premium + WAF  (the only public entry point)
//     /*      --> Static Web App (Standard), which accepts only this Front Door
//     /api/*  --> Function App through Private Link (public access disabled)
//   Function App --managed identity, VNet integration, private endpoints--> Blob storage (private)
//   Publisher (Entra ID) --> Blob storage, uploads approved PDFs
//   Telemetry: Log Analytics, Application Insights, availability tests, alerts
//
// The website and the documents it lists are intentionally public. Nothing else is: the
// storage container is private and only the API, which publishes PDFs marked approved=true,
// reads it.
//
// Bicep twin of a future Terraform template: keep the two equal.

import * as naming from 'modules/naming.bicep'

targetScope = 'subscription'

type governanceTagsType = {
  owner: string
  costCentre: string
  dataClassification: string
  support: string
}

// ---------------------------------------------------------------- target

@allowed(['dev', 'qa', 'uat', 'prod'])
param environment string
@description('Region for the Function, storage, network and monitoring. Limited to regions with Elastic Premium, private endpoints and zone support.')
@allowed([
  'westeurope'
  'northeurope'
  'swedencentral'
  'uksouth'
  'germanywestcentral'
  'francecentral'
  'eastus'
  'eastus2'
  'centralus'
  'westus2'
  'australiaeast'
])
param location string
@description('Static Web Apps is only offered in these regions, so it has its own setting. Front Door is global.')
@allowed(['westus2', 'centralus', 'eastus2', 'westeurope', 'eastasia'])
param staticWebAppLocation string
@description('Short workload code used in resource names.')
param workload string = 'doc'
param instance string = '001'
param applicationName string = 'Public Static Website with Document API'

// ---------------------------------------------------------------- governance

@description('Mandatory tags applied to every resource.')
param governanceTags governanceTagsType
param extraTags object = {}
@description('CanNotDelete lock on the resource group. On in uat and prod.')
param enableDeleteLock bool = false
@description('Monthly cost budget for the resource group. 0 disables it.')
param monthlyBudget int = 0
param budgetStartDate string = '2026-10-01T00:00:00Z'
param budgetContactEmails array = []

// ---------------------------------------------------------------- hosting

param previewEnvironmentsEnabled bool = true
@description('Optional custom domains served by Front Door, for example www.example.com. Each gets a managed certificate once its DNS validation record exists.')
param customDomains array = []
@description('WAF mode. Prevention blocks; Detection only logs. Prevention is forced in uat and prod.')
@allowed(['Prevention', 'Detection'])
param wafMode string = 'Detection'
@description('Spread the Function plan across availability zones (needs at least 2 instances). Off in dev and qa, on in uat and prod. Fixed at creation.')
param zoneRedundancyEnabled bool = false
param functionMaximumBurst int = 5
param nodeVersion string = '24'

// ---------------------------------------------------------------- network

@description('Take it from the IP plan; must not overlap the hub or other spokes.')
param vnetAddressSpace array
@description('At least /26, delegated to Microsoft.Web/serverFarms for Function VNet integration.')
param integrationSubnetPrefix string
param privateEndpointSubnetPrefix string
@description('Custom DNS servers for the VNet. Empty uses Azure DNS.')
param dnsServers array = []

// ---------------------------------------------------------------- documents

@description('Replication of the document storage: LRS, ZRS, GZRS or RAGZRS. ZRS in dev and qa, GZRS in uat and prod.')
@allowed(['LRS', 'ZRS', 'GZRS', 'RAGZRS'])
param storageReplicationType string = 'ZRS'
@description('Days deleted documents and containers can be recovered.')
param softDeleteRetentionDays int = 30
@description('Entra group object IDs that publish documents (Storage Blob Data Contributor).')
param publisherGroupIds array = []

// ---------------------------------------------------------------- monitoring

@description('One switch for all monitoring. Can be off in dev to save cost; always on in prod (forced on here).')
param enableMonitoring bool = true
param logRetentionDays int = 90
param logDailyQuotaGb int = -1
param availabilityFrequencySeconds int = 300
param alertEmailReceivers array = []
@secure()
param alertWebhookReceivers object = {}
param frontDoor5xxPercentThreshold int = 5
param originHealthPercentThreshold int = 90
param function5xxCountThreshold int = 5
param monitoringViewerPrincipalIds array = []
param monitoringOperatorPrincipalIds array = []

// ---------------------------------------------------------------- derived

// Prod always has monitoring and a blocking WAF, whatever the parameter files say.
var monitoringOn = enableMonitoring || environment == 'prod'
var wafModeEffective = contains(['uat', 'prod'], environment) ? 'Prevention' : wafMode

var tags = union(
  {
    environment: environment
    application: applicationName
    workload: workload
    audience: 'public'
    owner: governanceTags.owner
    'cost-centre': governanceTags.costCentre
    'data-classification': governanceTags.dataClassification
    support: governanceTags.support
    'managed-by': 'bicep'
  },
  extraTags
)

var blobDnsZone = 'privatelink.blob.core.windows.net'
var fileDnsZone = 'privatelink.file.core.windows.net'
var sitesDnsZone = 'privatelink.azurewebsites.net'

var sfx = naming.suffix(workload, environment, location, instance)
var names = {
  resourceGroup: naming.resourceGroupName(sfx)
  staticWebApp: naming.staticWebAppName(sfx)
  appServicePlan: naming.appServicePlanName(sfx)
  functionApp: naming.functionAppName(sfx)
  frontDoorProfile: naming.frontDoorProfileName(sfx)
  frontDoorEndpoint: naming.frontDoorEndpointName(sfx)
  waf: naming.wafPolicyName(sfx)
  logAnalytics: naming.logAnalyticsName(sfx)
  applicationInsights: naming.applicationInsightsName(sfx)
  actionGroup: naming.actionGroupName(sfx)
  actionGroupShort: naming.actionGroupShortName(workload, environment)
  budget: naming.budgetName(sfx)
  virtualNetwork: naming.virtualNetworkName(sfx)
  subnetIntegration: naming.subnetIntegrationName(sfx)
  subnetPrivateEndpoints: naming.subnetPrivateEndpointsName(sfx)
  nsgIntegration: naming.nsgIntegrationName(sfx)
  nsgPrivateEndpoints: naming.nsgPrivateEndpointsName(sfx)
  privateEndpointFunction: naming.privateEndpointFunctionName(sfx)
  privateEndpointBlob: naming.privateEndpointBlobName(sfx)
  privateEndpointFile: naming.privateEndpointFileName(sfx)
  storageAccount: naming.storageAccountName(sfx, subscription().subscriptionId)
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: names.resourceGroup
  location: location
  tags: tags
}

// ---------------------------------------------------------------- network

module network 'modules/network.bicep' = {
  scope: rg
  name: 'network'
  params: {
    name: names.virtualNetwork
    location: location
    addressSpace: vnetAddressSpace
    dnsServers: dnsServers
    subnetIntegrationName: names.subnetIntegration
    subnetPrivateEndpointsName: names.subnetPrivateEndpoints
    nsgIntegrationName: names.nsgIntegration
    nsgPrivateEndpointsName: names.nsgPrivateEndpoints
    integrationSubnetPrefix: integrationSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    privateDnsZones: [blobDnsZone, fileDnsZone, sitesDnsZone]
    tags: tags
  }
}

// ---------------------------------------------------------------- monitoring foundation

module monitoring 'modules/monitoring.bicep' = if (monitoringOn) {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    logAnalyticsName: names.logAnalytics
    applicationInsightsName: names.applicationInsights
    actionGroupName: names.actionGroup
    actionGroupShortName: names.actionGroupShort
    logRetentionDays: logRetentionDays
    logDailyQuotaGb: logDailyQuotaGb
    alertEmailReceivers: alertEmailReceivers
    alertWebhookReceivers: alertWebhookReceivers
    tags: tags
  }
}

// ---------------------------------------------------------------- documents

module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage'
  params: {
    name: names.storageAccount
    location: location
    privateEndpointBlobName: names.privateEndpointBlob
    privateEndpointFileName: names.privateEndpointFile
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    blobDnsZoneId: network.outputs.privateDnsZoneIds[blobDnsZone]
    fileDnsZoneId: network.outputs.privateDnsZoneIds[fileDnsZone]
    replicationType: storageReplicationType
    softDeleteRetentionDays: softDeleteRetentionDays
    publisherGroupIds: publisherGroupIds
    logAnalyticsWorkspaceId: monitoringOn ? monitoring.outputs.logAnalyticsWorkspaceId : ''
    tags: tags
  }
}

// ---------------------------------------------------------------- hosting

module functionApp 'modules/function-app.bicep' = {
  scope: rg
  name: 'function-app'
  params: {
    name: names.functionApp
    planName: names.appServicePlan
    location: location
    integrationSubnetId: network.outputs.integrationSubnetId
    privateEndpointName: names.privateEndpointFunction
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    sitesDnsZoneId: network.outputs.privateDnsZoneIds[sitesDnsZone]
    storageAccountName: storage.outputs.accountName
    containerName: storage.outputs.containerName
    applicationInsightsConnectionString: monitoringOn ? monitoring.outputs.applicationInsightsConnectionString : ''
    nodeVersion: nodeVersion
    zoneRedundancyEnabled: zoneRedundancyEnabled
    maximumBurst: functionMaximumBurst
    tags: tags
  }
}

module staticWebApp 'modules/static-web-app.bicep' = {
  scope: rg
  name: 'static-web-app'
  params: {
    name: names.staticWebApp
    location: staticWebAppLocation
    previewEnvironmentsEnabled: previewEnvironmentsEnabled
    tags: tags
  }
}

// ---------------------------------------------------------------- public edge

module waf 'modules/front-door-waf.bicep' = {
  scope: rg
  name: 'front-door-waf'
  params: {
    name: names.waf
    mode: wafModeEffective
    tags: tags
  }
}

module frontDoor 'modules/front-door.bicep' = {
  scope: rg
  name: 'front-door'
  params: {
    profileName: names.frontDoorProfile
    endpointName: names.frontDoorEndpoint
    location: location
    wafPolicyId: waf.outputs.id
    staticWebAppHostName: staticWebApp.outputs.defaultHostName
    functionAppId: functionApp.outputs.id
    functionAppHostName: functionApp.outputs.defaultHostName
    customDomains: customDomains
    logAnalyticsWorkspaceId: monitoringOn ? monitoring.outputs.logAnalyticsWorkspaceId : ''
    tags: tags
  }
}

// ---------------------------------------------------------------- alerts

var publicBaseUrl = empty(customDomains) ? 'https://${frontDoor.outputs.endpointHostName}' : 'https://${customDomains[0]}'

module alerts 'modules/alerts.bicep' = if (monitoringOn) {
  scope: rg
  name: 'alerts'
  params: {
    location: location
    nameSuffix: sfx
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    actionGroupId: monitoring.outputs.actionGroupId
    frontDoorProfileId: frontDoor.outputs.profileId
    functionAppId: functionApp.outputs.id
    availabilityUrls: {
      home: '${publicBaseUrl}/'
      api: '${publicBaseUrl}/api/documents'
    }
    availabilityFrequencySeconds: availabilityFrequencySeconds
    frontDoor5xxPercentThreshold: frontDoor5xxPercentThreshold
    originHealthPercentThreshold: originHealthPercentThreshold
    function5xxCountThreshold: function5xxCountThreshold
    tags: tags
  }
}

// Subscription Activity Log (deletions, role assignments, policy) is not exported here:
// one subscription holds one environment, so forward it from the platform diagnostics.

// ---------------------------------------------------------------- governance

module governance 'modules/governance.bicep' = {
  scope: rg
  name: 'governance'
  params: {
    environment: environment
    enableDeleteLock: enableDeleteLock || contains(['uat', 'prod'], environment)
    budgetName: names.budget
    monthlyBudget: monthlyBudget
    budgetStartDate: budgetStartDate
    budgetContactEmails: budgetContactEmails
    actionGroupId: monitoringOn ? monitoring.outputs.actionGroupId : ''
    viewerPrincipalIds: monitoringViewerPrincipalIds
    operatorPrincipalIds: monitoringOperatorPrincipalIds
  }
  // The lock goes on last, or it would block the deployment of what comes after it.
  dependsOn: [storage, functionApp, staticWebApp, frontDoor, alerts]
}

// ---------------------------------------------------------------- outputs

output resourceGroupName string = rg.name
output publicUrl string = publicBaseUrl
output frontDoorEndpointHostName string = frontDoor.outputs.endpointHostName
@description('Value the Static Web App requires in X-Azure-FDID (already inside staticWebAppConfigJson).')
output frontDoorId string = frontDoor.outputs.frontDoorId
output frontDoorProfileName string = frontDoor.outputs.profileName
output customDomainValidation array = frontDoor.outputs.customDomainValidation
output staticWebAppName string = staticWebApp.outputs.name
output staticWebAppHostName string = staticWebApp.outputs.defaultHostName
output functionAppName string = functionApp.outputs.name
output functionPrincipalId string = functionApp.outputs.principalId
output storageAccountName string = storage.outputs.accountName
output containerName string = storage.outputs.containerName
output virtualNetworkId string = network.outputs.virtualNetworkId
output monitoringWorkspaceId string = monitoringOn ? monitoring.outputs.logAnalyticsWorkspaceId : ''

@description('staticwebapp.config.json for the frontend: accepts only this Front Door, and sets the security headers. Store it as the pipeline\'s SWA_CONFIG_JSON.')
output staticWebAppConfigJson string = string({
  networking: {
    allowedIpRanges: ['AzureFrontDoor.Backend']
  }
  forwardingGateway: {
    requiredHeaders: {
      'X-Azure-FDID': frontDoor.outputs.frontDoorId
    }
    allowedForwardedHosts: union([frontDoor.outputs.endpointHostName], customDomains)
  }
  globalHeaders: {
    'Content-Security-Policy': 'default-src \'self\'; script-src \'self\'; style-src \'self\'; font-src \'self\'; img-src \'self\' data:; connect-src \'self\'; object-src \'none\'; base-uri \'self\'; form-action \'none\'; frame-ancestors \'none\'; upgrade-insecure-requests'
    'Strict-Transport-Security': 'max-age=31536000'
    'X-Content-Type-Options': 'nosniff'
    'X-Frame-Options': 'DENY'
    'Referrer-Policy': 'strict-origin-when-cross-origin'
    'Permissions-Policy': 'camera=(), geolocation=(), microphone=(), payment=(), usb=()'
  }
})

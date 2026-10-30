// Privately accessible static website, for internal users only
// (anyone signing in with APEX Entra: employees, APEX companies, contractors).
//
//   APEX user on the corporate network --private DNS--> private endpoint
//     --> Static Web App (public access off, APEX Entra sign-in required)
//   In-VNet probe --> site ; probe + diagnostics --> Monitor Private Link --> Log Analytics
//
// Nothing in this design is reachable from the internet.

import * as naming from 'modules/naming.bicep'

targetScope = 'subscription'

type governanceTagsType = {
  // Mandatory
  owner: string
  costCentre: string
  dataClassification: string
  support: string
  // Recommended: tagged when set, left off when not
  businessUnit: string?
  criticality: ('Low' | 'Medium' | 'High' | 'Mission-critical')?
  projectCode: string?
}

// ---------------------------------------------------------------- target

@allowed(['dev', 'qa', 'uat', 'prod'])
param environment string
@description('Region for everything. Static Web Apps is only offered in westus2, centralus, eastus2, westeurope and eastasia.')
@allowed(['westus2', 'centralus', 'eastus2', 'westeurope', 'eastasia'])
param location string
@description('Short workload code used in resource names.')
param workload string = 'swi'
param instance string = '001'
param applicationName string = 'Internal Static Website'

// ---------------------------------------------------------------- governance

@description('Mandatory tags (owner, costCentre, dataClassification, support) and recommended tags (businessUnit, criticality, projectCode) applied to every resource.')
param governanceTags governanceTagsType
param extraTags object = {}
param enableDeleteLock bool = false
@description('Monthly cost budget for the resource group. 0 disables it.')
param monthlyBudget int = 0
param budgetStartDate string = '2026-10-01T00:00:00Z'
param budgetContactEmails array = []

// ---------------------------------------------------------------- hosting

@description('Pull-request previews. They are private too, reachable only from the APEX network.')
param previewEnvironmentsEnabled bool = true

// ---------------------------------------------------------------- network

@description('Take it from the APEX IP plan; must not overlap the hub or other spokes.')
param vnetAddressSpace array
param privateEndpointSubnetPrefix string
@description('At least /27, delegated to Container Apps.')
param probeSubnetPrefix string
@description('Custom DNS servers for the VNet (for example the hub DNS resolver). Empty uses Azure DNS.')
param dnsServers array = []
@description('Optional APEX hub VNet: spoke-side peering plus Private DNS zone links.')
param hubVirtualNetworkId string = ''
param useHubGateway bool = false

// ---------------------------------------------------------------- sign-in (APEX Entra only)

// The groups allowed to sign in are ALLOWED_GROUP_IDS in deployment.env: scripts/deploy.sh assigns
// them to the app registration, and Entra refuses everyone else in APEX before the site sees a request.
@description('Client ID of the app registration. scripts/deploy.sh creates it and passes it in.')
param entraClientId string
@secure()
@description('Client secret of the app registration. scripts/deploy.sh creates it and passes it in; it is never stored in this repository.')
param entraClientSecret string

// ---------------------------------------------------------------- monitoring

@description('One switch for all monitoring. Can be off in dev to save cost; always on in prod (forced on here).')
param enableMonitoring bool = true
param logRetentionDays int = 90
param logDailyQuotaGb int = -1
@description('true lets viewers open the dashboard and query logs from the Azure portal anywhere they can sign in; false requires the APEX network. Telemetry ingestion is always private.')
param monitoringQueryFromInternet bool = true
@description('Spread the availability probe\'s Container Apps environment across availability zones. Fixed at creation.')
param probeZoneRedundancyEnabled bool = false
param probeCron string = '*/5 * * * *'
@description('Image for the in-network probe. Mirror it into an APEX registry for a fully private pull.')
param probeImage string = 'mcr.microsoft.com/azure-cli:latest'
param alertEmailReceivers array = []
@secure()
param alertWebhookReceivers object = {}
param alertThresholds object = {}
@description('Azure incident alert for the whole subscription. When environments share a subscription, keep it true in only one of them.')
param enableServiceHealthAlert bool = true
param exportActivityLog bool = false
param monitoringViewerPrincipalIds array = []
param monitoringOperatorPrincipalIds array = []

// ---------------------------------------------------------------- derived

// Prod always has monitoring, whatever the parameter files say.
var monitoringOn = enableMonitoring || environment == 'prod'

var tags = union(
  {
    environment: environment
    application: applicationName
    workload: workload
    audience: 'internal'
    owner: governanceTags.owner
    'cost-centre': governanceTags.costCentre
    'data-classification': governanceTags.dataClassification
    support: governanceTags.support
    'managed-by': 'bicep'
    'golden-template': 'privately-accessible-static-website-bicep'
  },
  empty(governanceTags.?businessUnit) ? {} : { 'business-unit': governanceTags.?businessUnit! },
  empty(governanceTags.?criticality) ? {} : { criticality: governanceTags.?criticality! },
  empty(governanceTags.?projectCode) ? {} : { 'project-code': governanceTags.?projectCode! },
  extraTags
)

var monitorDnsZones = [
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
  'privatelink.blob.core.windows.net'
]

var sfx = naming.suffix(workload, environment, location, instance)
var names = {
  resourceGroup: naming.resourceGroupName(sfx)
  staticWebApp: naming.staticWebAppName(sfx)
  logAnalytics: naming.logAnalyticsName(sfx)
  applicationInsights: naming.applicationInsightsName(sfx)
  actionGroup: naming.actionGroupName(sfx)
  actionGroupShort: naming.actionGroupShortName(workload, environment)
  budget: naming.budgetName(sfx)
  virtualNetwork: naming.virtualNetworkName(sfx)
  subnetPrivateEndpoints: naming.subnetPrivateEndpointsName(sfx)
  subnetProbe: naming.subnetProbeName(sfx)
  nsgPrivateEndpoints: naming.nsgPrivateEndpointsName(sfx)
  nsgProbe: naming.nsgProbeName(sfx)
  privateLinkScope: naming.privateLinkScopeName(sfx)
  privateEndpointSite: naming.privateEndpointSiteName(sfx)
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
    subnetPrivateEndpointsName: names.subnetPrivateEndpoints
    subnetProbeName: names.subnetProbe
    nsgPrivateEndpointsName: names.nsgPrivateEndpoints
    nsgProbeName: names.nsgProbe
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    probeSubnetPrefix: probeSubnetPrefix
    privateDnsZones: monitoringOn ? monitorDnsZones : []
    hubVirtualNetworkId: hubVirtualNetworkId
    useHubGateway: useHubGateway
    tags: tags
  }
}

// ---------------------------------------------------------------- hosting

module staticWebApp 'modules/static-web-app.bicep' = {
  scope: rg
  name: 'static-web-app'
  params: {
    name: names.staticWebApp
    location: location
    sku: 'Standard' // private endpoints and custom auth need Standard
    previewEnvironmentsEnabled: previewEnvironmentsEnabled
    publicNetworkAccessEnabled: false
    appSettings: {
      AZURE_CLIENT_ID: entraClientId
      AZURE_CLIENT_SECRET: entraClientSecret
    }
    tags: tags
  }
}

module sitePrivateLink 'modules/site-private-link.bicep' = {
  scope: rg
  name: 'site-private-link'
  params: {
    location: location
    defaultHostName: staticWebApp.outputs.defaultHostName
    zoneLinkName: 'link-${names.virtualNetwork}'
    virtualNetworkId: network.outputs.virtualNetworkId
    hubVirtualNetworkId: hubVirtualNetworkId
    privateEndpointName: names.privateEndpointSite
    subnetId: network.outputs.privateEndpointSubnetId
    staticWebAppId: staticWebApp.outputs.id
    tags: tags
  }
}

// ---------------------------------------------------------------- monitoring

module monitoring 'modules/monitoring.bicep' = if (monitoringOn) {
  scope: rg
  name: 'monitoring'
  params: {
    location: location
    nameSuffix: sfx
    logAnalyticsName: names.logAnalytics
    applicationInsightsName: names.applicationInsights
    actionGroupName: names.actionGroup
    actionGroupShortName: names.actionGroupShort
    logRetentionDays: logRetentionDays
    logDailyQuotaGb: logDailyQuotaGb
    // Private site: no internet web tests; the in-VNet probe reports instead.
    customAvailabilityTestNames: ['site']
    internetIngestionEnabled: false
    internetQueryEnabled: monitoringQueryFromInternet
    alertEmailReceivers: alertEmailReceivers
    alertWebhookReceivers: alertWebhookReceivers
    alertThresholds: alertThresholds
    serviceHealthAlertEnabled: enableServiceHealthAlert
    viewerPrincipalIds: monitoringViewerPrincipalIds
    operatorPrincipalIds: monitoringOperatorPrincipalIds
    tags: tags
  }
}

module monitorPrivateLink 'modules/monitor-private-link.bicep' = if (monitoringOn) {
  scope: rg
  name: 'monitor-private-link'
  params: {
    name: names.privateLinkScope
    location: location
    subnetId: network.outputs.privateEndpointSubnetId
    linkedResourceIds: {
      law: monitoring.outputs.logAnalyticsWorkspaceId
      appi: monitoring.outputs.applicationInsightsId
    }
    privateDnsZoneIds: [for zone in monitorDnsZones: network.outputs.privateDnsZoneIds[zone]]
    queryAccessMode: monitoringQueryFromInternet ? 'Open' : 'PrivateOnly'
    tags: tags
  }
}

module availabilityProbe 'modules/availability-probe.bicep' = if (monitoringOn) {
  scope: rg
  name: 'availability-probe'
  params: {
    nameSuffix: sfx
    location: location
    subnetId: network.outputs.probeSubnetId
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    cronExpression: probeCron
    zoneRedundancyEnabled: probeZoneRedundancyEnabled
    image: probeImage
    tags: tags
    // /healthz.html is the one anonymous route; everything else needs APEX sign-in.
    tests: {
      site: {
        url: 'https://${staticWebApp.outputs.defaultHostName}/healthz.html'
      }
    }
  }
  dependsOn: [sitePrivateLink, monitorPrivateLink]
}

// Subscription Activity Log: deletions, role assignments, policy and service health events.
resource activityLogExport 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (monitoringOn && exportActivityLog) {
  name: 'activity-log-to-${names.logAnalytics}'
  properties: {
    workspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logs: [
      for category in ['Administrative', 'Security', 'ServiceHealth', 'Alert', 'Policy', 'ResourceHealth']: {
        category: category
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------------- governance

module governance 'modules/governance.bicep' = {
  scope: rg
  name: 'governance'
  params: {
    environment: environment
    enableDeleteLock: enableDeleteLock
    budgetName: names.budget
    monthlyBudget: monthlyBudget
    budgetStartDate: budgetStartDate
    budgetContactEmails: budgetContactEmails
    actionGroupId: monitoringOn ? monitoring.outputs.actionGroupId : ''
  }
  // The lock goes on last, or it would block the deployment of what comes after it.
  dependsOn: [staticWebApp, sitePrivateLink, monitoring, monitorPrivateLink, availabilityProbe]
}

// ---------------------------------------------------------------- outputs

output resourceGroupName string = rg.name
output staticWebAppName string = staticWebApp.outputs.name
@description('Resolves to the private endpoint from the VNet and any linked hub; unreachable from the internet.')
output privateUrl string = 'https://${staticWebApp.outputs.defaultHostName}/'
output staticWebAppHostName string = staticWebApp.outputs.defaultHostName
output entraClientId string = entraClientId
output virtualNetworkId string = network.outputs.virtualNetworkId
@description('Zones the APEX DNS (or hub resolver) must be able to resolve for users to reach the site.')
output privateDnsZones array = union(objectKeys(network.outputs.privateDnsZoneIds), [sitePrivateLink.outputs.zoneName])
output monitoringDashboardUrl string = monitoringOn ? monitoring.outputs.workbookPortalUrl : ''

@description('staticwebapp.config.json for content/privately-accessible-static-website/: APEX-only sign-in, anonymous /healthz.html for the probe, security headers. Store it as the pipeline\'s SWA_CONFIG_JSON.')
output staticWebAppConfigJson string = string({
  auth: {
    identityProviders: {
      azureActiveDirectory: {
        registration: {
          openIdIssuer: 'https://login.microsoftonline.com/${tenant().tenantId}/v2.0'
          clientIdSettingName: 'AZURE_CLIENT_ID'
          clientSecretSettingName: 'AZURE_CLIENT_SECRET'
        }
      }
    }
  }
  routes: [
    { route: '/healthz.html', allowedRoles: ['anonymous'] }
    { route: '/.auth/login/github', statusCode: 404 }
    { route: '/.auth/login/twitter', statusCode: 404 }
    { route: '/*', allowedRoles: ['authenticated'] }
  ]
  responseOverrides: {
    '401': {
      redirect: '/.auth/login/aad?post_login_redirect_uri=.referrer'
      statusCode: 302
    }
  }
  globalHeaders: {
    'Content-Security-Policy': 'default-src \'self\'; style-src \'self\'; font-src \'self\'; img-src \'self\' data:; script-src \'self\'; frame-ancestors \'none\'; base-uri \'self\'; form-action \'self\''
    'X-Content-Type-Options': 'nosniff'
    'Referrer-Policy': 'strict-origin-when-cross-origin'
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains'
    'Cache-Control': 'private, no-store'
  }
})

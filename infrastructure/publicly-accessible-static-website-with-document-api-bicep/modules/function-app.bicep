// The document API: an Azure Functions app on an Elastic Premium plan.
//
//   - public network access is off; Front Door reaches it through Private Link
//   - outbound traffic goes through the VNet (route all), so storage is reached over its private endpoints
//   - the system-assigned identity reads documents (Storage Blob Data Reader); no key, SAS or connection
//     string for the documents ever reaches the app
//
// The Function host itself still uses the storage account key (AzureWebJobsStorage and its content
// share), which is why the storage account keeps shared-key access on.

param name string
param planName string
param location string
param integrationSubnetId string
param privateEndpointName string
param privateEndpointSubnetId string
@description('privatelink.azurewebsites.net')
param sitesDnsZoneId string
param storageAccountName string
param containerName string
param applicationInsightsConnectionString string = ''
@description('Node.js major version for the Linux runtime.')
param nodeVersion string = '24'
@description('Spread the plan across availability zones. Needs at least 2 instances; fixed at creation.')
param zoneRedundancyEnabled bool = false
@minValue(1)
@maxValue(20)
param maximumBurst int = 5
param tags object = {}

var storageBlobDataReader = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var minimumInstances = zoneRedundancyEnabled ? 2 : 1

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var hostStorageConnection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: minimumInstances
  }
  properties: {
    reserved: true // Linux
    zoneRedundant: zoneRedundancyEnabled
    maximumElasticWorkerCount: max(maximumBurst, minimumInstances)
  }
}

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: integrationSubnetId
    vnetRouteAllEnabled: true
    vnetContentShareEnabled: true
    siteConfig: {
      linuxFxVersion: 'NODE|${nodeVersion}'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      alwaysOn: false // Elastic Premium scales on demand and has no Always On
      minimumElasticInstanceCount: minimumInstances
      appSettings: concat(
        [
          { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
          { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
          { name: 'AzureWebJobsStorage', value: hostStorageConnection }
          { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: hostStorageConnection }
          { name: 'WEBSITE_CONTENTSHARE', value: toLower(name) }
          { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
          { name: 'DATA_STORAGE_ACCOUNT', value: storageAccountName }
          { name: 'DATA_CONTAINER', value: containerName }
        ],
        empty(applicationInsightsConnectionString)
          ? []
          : [{ name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsightsConnectionString }]
      )
    }
  }
}

// Read-only on the documents: the API lists and streams, it never writes.
resource reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, app.id, storageBlobDataReader)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReader)
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reached from the corporate network (deployment, Kudu) and, through Private Link, by Front Door.
module endpoint 'private-endpoint.bicep' = {
  name: 'function-endpoint'
  params: {
    name: privateEndpointName
    location: location
    subnetId: privateEndpointSubnetId
    targetResourceId: app.id
    groupIds: ['sites']
    privateDnsZoneIds: [sitesDnsZoneId]
    tags: tags
  }
}

output id string = app.id
output name string = app.name
output defaultHostName string = app.properties.defaultHostName
output principalId string = app.identity.principalId
output planId string = plan.id

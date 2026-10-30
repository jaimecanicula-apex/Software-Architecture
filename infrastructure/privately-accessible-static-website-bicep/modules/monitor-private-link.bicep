// Azure Monitor Private Link Scope: telemetry from inside the VNet (the
// availability probe) reaches Log Analytics and Application Insights over a
// private endpoint instead of the internet.

param name string
param location string
param subnetId string
@description('Log Analytics workspace and Application Insights IDs, keyed by a short name.')
param linkedResourceIds object
@description('IDs of the Azure Monitor private DNS zones.')
param privateDnsZoneIds array
@description('Open lets viewers query from the Azure portal over the internet; PrivateOnly requires them to be on the APEX network.')
@allowed(['Open', 'PrivateOnly'])
param queryAccessMode string = 'Open'
param tags object = {}

resource scope 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: name
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: queryAccessMode
    }
  }
}

resource scopedServices 'microsoft.insights/privateLinkScopes/scopedResources@2021-07-01-preview' = [
  for item in items(linkedResourceIds): {
    parent: scope
    name: 'ampls-${item.key}'
    properties: {
      linkedResourceId: item.value
    }
  }
]

module endpoint 'private-endpoint.bicep' = {
  name: 'monitor-endpoint'
  params: {
    name: 'pe-${name}'
    location: location
    subnetId: subnetId
    targetResourceId: scope.id
    groupIds: ['azuremonitor']
    privateDnsZoneIds: privateDnsZoneIds
    tags: tags
  }
  dependsOn: [scopedServices]
}

output id string = scope.id

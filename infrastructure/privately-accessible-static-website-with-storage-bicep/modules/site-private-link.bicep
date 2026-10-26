// The Static Web App's private endpoint and its Private DNS zone. The zone name
// follows the app's partition (<name>.<partition>.azurestaticapps.net), which is
// only known once the app exists, so this is a module: its parameters can carry
// a value that is not known until deployment.

param location string
param defaultHostName string
param zoneLinkName string
param virtualNetworkId string
param hubVirtualNetworkId string = ''
param privateEndpointName string
param subnetId string
param staticWebAppId string
param tags object = {}

var hostParts = split(defaultHostName, '.')
var zoneName = length(hostParts) == 4 ? 'privatelink.${hostParts[1]}.azurestaticapps.net' : 'privatelink.azurestaticapps.net'

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource spokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: zoneLinkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource hubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (!empty(hubVirtualNetworkId)) {
  parent: zone
  name: 'link-hub'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVirtualNetworkId
    }
  }
}

module endpoint 'private-endpoint.bicep' = {
  name: 'site-endpoint'
  params: {
    name: privateEndpointName
    location: location
    subnetId: subnetId
    targetResourceId: staticWebAppId
    groupIds: ['staticSites']
    privateDnsZoneIds: [zone.id]
    tags: tags
  }
}

output zoneName string = zone.name
output privateEndpointId string = endpoint.outputs.id

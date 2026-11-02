// One private endpoint with its DNS zone group, so the service resolves to a
// private IP inside the VNet (and any linked hub).

param name string
param location string
param subnetId string
param targetResourceId string
@description('For example [\'staticSites\'], [\'blob\'] or [\'azuremonitor\'].')
param groupIds array
param privateDnsZoneIds array
param tags object = {}

resource endpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    customNetworkInterfaceName: 'nic-${name}'
    privateLinkServiceConnections: [
      {
        name: 'psc-${name}'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, i) in privateDnsZoneIds: {
        name: 'config-${i}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}

output id string = endpoint.id

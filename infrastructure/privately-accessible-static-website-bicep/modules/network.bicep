// Spoke network for the internal design: one VNet, a subnet for private endpoints,
// a delegated subnet for the in-network availability probe, NSGs that refuse
// anything from the internet, and the Private DNS zones those endpoints need.

param name string
param location string
param addressSpace array
param dnsServers array = []
param subnetPrivateEndpointsName string
param subnetProbeName string
param nsgPrivateEndpointsName string
param nsgProbeName string
param privateEndpointSubnetPrefix string
@description('At least /27, delegated to Container Apps.')
param probeSubnetPrefix string
@description('Fixed-name zones. The Static Web App zone depends on the app partition, so site-private-link.bicep creates it.')
param privateDnsZones array
@description('Optional APEX hub VNet: spoke-side peering plus Private DNS zone links.')
param hubVirtualNetworkId string = ''
param useHubGateway bool = false
param tags object = {}

var hubEnabled = !empty(hubVirtualNetworkId)

resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgPrivateEndpointsName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsFromVirtualNetwork'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'DenyInternetInbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource nsgProbe 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgProbeName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenyInternetInbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressSpace
    }
    dhcpOptions: {
      dnsServers: dnsServers
    }
    subnets: [
      {
        name: subnetPrivateEndpointsName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          networkSecurityGroup: {
            id: nsgPrivateEndpoints.id
          }
        }
      }
      {
        name: subnetProbeName
        properties: {
          addressPrefix: probeSubnetPrefix
          networkSecurityGroup: {
            id: nsgProbe.id
          }
          delegations: [
            {
              name: 'container-apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in privateDnsZones: {
    name: zone
    location: 'global'
    tags: tags
  }
]

resource spokeLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in privateDnsZones: {
    parent: zones[i]
    name: 'link-${name}'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

resource hubLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in privateDnsZones: if (hubEnabled) {
    parent: zones[i]
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
]

// Spoke side of the hub peering. The hub side is owned by the platform team.
resource toHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = if (hubEnabled) {
  parent: vnet
  name: 'peer-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVirtualNetworkId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    useRemoteGateways: useHubGateway
  }
}

output virtualNetworkId string = vnet.id
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, subnetPrivateEndpointsName)
output probeSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, subnetProbeName)
@description('Zone name => zone ID.')
output privateDnsZoneIds object = toObject(privateDnsZones, zone => zone, zone => resourceId('Microsoft.Network/privateDnsZones', zone))

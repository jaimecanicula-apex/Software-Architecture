// Spoke network: one VNet, a subnet delegated to the Function's VNet integration,
// a subnet for private endpoints, NSGs, and the Private DNS zones those endpoints
// need. The Function's outbound traffic and its storage access stay on this VNet.

param name string
param location string
param addressSpace array
param dnsServers array = []
param subnetIntegrationName string
param subnetPrivateEndpointsName string
param nsgIntegrationName string
param nsgPrivateEndpointsName string
@description('At least /26 for Elastic Premium VNet integration; delegated to Microsoft.Web/serverFarms.')
param integrationSubnetPrefix string
param privateEndpointSubnetPrefix string
@description('Zones the private endpoints need, for example privatelink.blob.core.windows.net.')
param privateDnsZones array
param tags object = {}

resource nsgIntegration 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgIntegrationName
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
        name: subnetIntegrationName
        properties: {
          addressPrefix: integrationSubnetPrefix
          networkSecurityGroup: {
            id: nsgIntegration.id
          }
          delegations: [
            {
              name: 'web-server-farms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
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

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
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

output virtualNetworkId string = vnet.id
output integrationSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, subnetIntegrationName)
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', name, subnetPrivateEndpointsName)
@description('Zone name => zone ID.')
output privateDnsZoneIds object = toObject(privateDnsZones, zone => zone, zone => resourceId('Microsoft.Network/privateDnsZones', zone))

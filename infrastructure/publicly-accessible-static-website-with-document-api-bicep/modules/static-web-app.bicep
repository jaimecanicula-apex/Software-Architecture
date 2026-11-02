// Azure Static Web App hosting the build-free frontend. Content is deployed by the
// pipeline, not by Bicep. The app is reachable only through Front Door: the
// staticwebapp.config.json that main.bicep outputs allows only AzureFrontDoor.Backend,
// requires this profile's X-Azure-FDID header and lists the permitted forwarded hosts.
// Those settings need the Standard plan.

param name string
@description('Static Web Apps is only offered in a few regions.')
@allowed(['westus2', 'centralus', 'eastus2', 'westeurope', 'eastasia'])
param location string
@description('Allow pull-request preview environments. Origin restrictions apply to them too, so they may not be browsable directly.')
param previewEnvironmentsEnabled bool = true
param tags object = {}

resource site 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    stagingEnvironmentPolicy: previewEnvironmentsEnabled ? 'Enabled' : 'Disabled'
    allowConfigFileUpdates: true
  }
}

output id string = site.id
output name string = site.name
output defaultHostName string = site.properties.defaultHostname

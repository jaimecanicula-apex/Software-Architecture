// Azure Static Web App hosting the build-free site in content/privately-accessible-static-website-with-storage/.
// Content is deployed by the GitHub Actions or Azure Pipelines delivery option, not by Bicep.

param name string
@description('Static Web Apps is only offered in a few regions.')
@allowed(['westus2', 'centralus', 'eastus2', 'westeurope', 'eastasia'])
param location string
@allowed(['Free', 'Standard'])
param sku string = 'Standard'
@description('Allow pull-request preview environments.')
param previewEnvironmentsEnabled bool = true
@description('false makes the site reachable only through its private endpoint (internal design).')
param publicNetworkAccessEnabled bool = true
param appSettings object = {}
param tags object = {}

resource site 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    stagingEnvironmentPolicy: previewEnvironmentsEnabled ? 'Enabled' : 'Disabled'
    allowConfigFileUpdates: true
    publicNetworkAccess: publicNetworkAccessEnabled ? 'Enabled' : 'Disabled'
  }
}

resource settings 'Microsoft.Web/staticSites/config@2023-12-01' = {
  parent: site
  name: 'appsettings'
  properties: appSettings
}

output id string = site.id
output name string = site.name
output defaultHostName string = site.properties.defaultHostname

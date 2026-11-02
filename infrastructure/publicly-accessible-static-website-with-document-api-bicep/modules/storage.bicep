// One storage account for the published documents and the Function host (its
// runtime state and content file share). A private container holds the documents;
// the Function reads them with its managed identity, publishers write with Entra ID.
//
// Reference baseline, deliberately not the hardest possible one: shared-key access
// stays on because the Function host needs it, and the public endpoint accepts
// authenticated requests so publishers need no network path. See the README's
// Design decisions table for the trade-off and the hardened alternative.

param name string
param location string
param privateEndpointBlobName string
param privateEndpointFileName string
param privateEndpointSubnetId string
@description('privatelink.blob.core.windows.net')
param blobDnsZoneId string
@description('privatelink.file.core.windows.net')
param fileDnsZoneId string
@description('LRS, ZRS, GZRS or RAGZRS. ZRS in dev and qa, GZRS in uat and prod.')
@allowed(['LRS', 'ZRS', 'GZRS', 'RAGZRS'])
param replicationType string = 'ZRS'
param containerName string = 'documents'
@description('Days deleted blobs and containers can be recovered.')
@minValue(1)
@maxValue(365)
param softDeleteRetentionDays int = 30
@description('Entra groups that publish documents (Storage Blob Data Contributor). Prefer groups to users.')
param publisherGroupIds array = []
@description('Send blob read, write and delete logs here. Empty turns it off.')
param logAnalyticsWorkspaceId string = ''
param tags object = {}

var storageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_${replicationType}'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: false
    deleteRetentionPolicy: {
      enabled: true
      days: softDeleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: softDeleteRetentionDays
    }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

module blobEndpoint 'private-endpoint.bicep' = {
  name: 'storage-blob-endpoint'
  params: {
    name: privateEndpointBlobName
    location: location
    subnetId: privateEndpointSubnetId
    targetResourceId: account.id
    groupIds: ['blob']
    privateDnsZoneIds: [blobDnsZoneId]
    tags: tags
  }
}

// The Function host keeps its content share here, so the file endpoint is needed too.
module fileEndpoint 'private-endpoint.bicep' = {
  name: 'storage-file-endpoint'
  params: {
    name: privateEndpointFileName
    location: location
    subnetId: privateEndpointSubnetId
    targetResourceId: account.id
    groupIds: ['file']
    privateDnsZoneIds: [fileDnsZoneId]
    tags: tags
  }
}

resource publishers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for groupId in publisherGroupIds: {
    name: guid(account.id, groupId, storageBlobDataContributor)
    scope: account
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributor)
      principalId: groupId
      principalType: 'Group'
    }
  }
]

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-blob'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

output id string = account.id
output accountName string = account.name
output containerName string = container.name

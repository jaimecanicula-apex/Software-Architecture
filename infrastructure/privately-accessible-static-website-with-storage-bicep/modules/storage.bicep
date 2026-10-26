// Shared file library: one private blob container that signed-in users read and
// write with their own Entra identity. No account keys, no public access.
//
// Users get a custom role scoped to the one container: blob read, write and
// delete plus blob tag read, so the page can hide files that malware scanning
// has flagged.

param name string
param roleName string
param privateEndpointName string
param location string
param privateEndpointSubnetId string
@description('privatelink.blob.core.windows.net')
param privateDnsZoneId string
@description('LRS, ZRS, GZRS or RAGZRS. ZRS in dev/qa, GZRS in uat/prod.')
@allowed(['LRS', 'ZRS', 'GZRS', 'RAGZRS'])
param replicationType string = 'ZRS'
param containerName string = 'files'
@description('Days deleted files, deleted containers and old file versions are kept.')
@minValue(1)
@maxValue(365)
param softDeleteRetentionDays int = 7
@description('Origins the browser calls from: the site\'s own https host names.')
param corsAllowedOrigins array
@description('Entra groups whose members can list, upload, download and delete files.')
param userGroupIds array = []
@description('Defender for Storage malware scanning on upload. Flagged files get a blob index tag that the page hides.')
param malwareScanningEnabled bool = false
@description('Scanning, and its charge, stops after this many GB a month. -1 for no cap.')
param malwareScanCapGbPerMonth int = 1000
@description('Send blob read, write and delete logs here. Empty turns it off.')
param logAnalyticsWorkspaceId string = ''
param tags object = {}

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
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Disabled'
    allowCrossTenantReplication: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: softDeleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: softDeleteRetentionDays
    }
    cors: {
      corsRules: [
        {
          allowedOrigins: corsAllowedOrigins
          allowedMethods: ['GET', 'HEAD', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['authorization', 'content-type', 'x-ms-*', 'if-match', 'if-none-match']
          exposedHeaders: ['x-ms-*', 'etag', 'content-length', 'content-type']
          maxAgeInSeconds: 3600
        }
      ]
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

// Old versions are billed as storage, so they are removed after the retention period.
resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'delete-old-versions'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
            }
            actions: {
              version: {
                delete: {
                  daysAfterCreationGreaterThan: softDeleteRetentionDays
                }
              }
            }
          }
        }
      ]
    }
  }
}

module endpoint 'private-endpoint.bicep' = {
  name: 'storage-endpoint'
  params: {
    name: privateEndpointName
    location: location
    subnetId: privateEndpointSubnetId
    targetResourceId: account.id
    groupIds: ['blob']
    privateDnsZoneIds: [privateDnsZoneId]
    tags: tags
  }
}

resource filesUser 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(account.id, roleName)
  properties: {
    roleName: roleName
    description: 'List, read, upload, overwrite and delete blobs, and read blob tags.'
    type: 'CustomRole'
    permissions: [
      {
        actions: []
        dataActions: [
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'
        ]
      }
    ]
    assignableScopes: [account.id]
  }
}

resource users 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for groupId in userGroupIds: {
    name: guid(container.id, groupId, filesUser.id)
    scope: container
    properties: {
      roleDefinitionId: filesUser.id
      principalId: groupId
      principalType: 'Group'
    }
  }
]

resource defender 'Microsoft.Security/defenderForStorageSettings@2022-12-01-preview' = if (malwareScanningEnabled) {
  name: 'current'
  scope: account
  properties: {
    isEnabled: true
    malwareScanning: {
      onUpload: {
        isEnabled: true
        capGBPerMonth: malwareScanCapGbPerMonth
      }
    }
    sensitiveDataDiscovery: {
      isEnabled: false
    }
    overrideSubscriptionLevelSettings: true
  }
}

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
output malwareScanningEnabled bool = malwareScanningEnabled

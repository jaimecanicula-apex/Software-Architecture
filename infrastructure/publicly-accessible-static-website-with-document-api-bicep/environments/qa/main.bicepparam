// QA: publicly accessible static website with a document API.
// Replace every placeholder before the first deployment. The subscription and
// tenant are in deployment.env, next to this file.
using '../../main.bicep'

param environment = 'qa'
param location = 'westeurope'
// Static Web Apps is only offered in westus2, centralus, eastus2, westeurope and eastasia.
param staticWebAppLocation = 'westeurope'
param workload = 'doc'
param instance = '001'

param governanceTags = {
  owner: '<owner team>'
  costCentre: '<cost centre>'
  dataClassification: 'Public'
  support: '<support group or email>'
}

// The delete lock is forced on in uat and prod regardless of this value.
param enableDeleteLock = false
param monthlyBudget = 600
param budgetStartDate = '2026-10-01T00:00:00Z'
// param budgetContactEmails = ['finops@example.com']

param previewEnvironmentsEnabled = true
// param customDomains = ['www.example.com'] // each needs a DNS validation record, see the README

// Prevention is forced in uat and prod; dev and qa may start in Detection while rules are tuned.
param wafMode = 'Detection'

// Resilience, fixed at creation. Off in dev and qa, on in uat and prod. With zones on the plan runs at
// least 2 instances, and storage must use a zone-redundant replication (ZRS, GZRS or RAGZRS).
param zoneRedundancyEnabled = false
param functionMaximumBurst = 3
param nodeVersion = '24'

// Network: take the ranges from the IP plan (these are placeholders).
param vnetAddressSpace = ['10.242.0.0/24']
param integrationSubnetPrefix = '10.242.0.0/26'
param privateEndpointSubnetPrefix = '10.242.0.64/27'
// param dnsServers = ['<DNS resolver IP>']

// Documents: one private container. Replication and retention are policy per environment.
param storageReplicationType = 'ZRS'
param softDeleteRetentionDays = 14
// Entra group object IDs allowed to upload documents (Storage Blob Data Contributor).
param publisherGroupIds = empty(readEnvironmentVariable('PUBLISHER_GROUP_IDS', '')) ? [] : split(readEnvironmentVariable('PUBLISHER_GROUP_IDS', ''), ',')

// Monitoring: one switch for all of it; always on in prod.
param enableMonitoring = true
param logRetentionDays = 30
param availabilityFrequencySeconds = 300
param alertEmailReceivers = [
  // 'alerts@example.com'
]
param frontDoor5xxPercentThreshold = 5
param originHealthPercentThreshold = 90
param function5xxCountThreshold = 5
param monitoringViewerPrincipalIds = [
  // '<entra-group-object-id: service owners>'
]
param monitoringOperatorPrincipalIds = [
  // '<entra-group-object-id: operations>'
]

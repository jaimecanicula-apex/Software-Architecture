// PROD: privately accessible static website with storage (internal users only).
// Replace every placeholder before the first deployment. The subscription and
// tenant are in deployment.env, next to this file.
using '../../main.bicep'

param environment = 'prod'
param location = 'westeurope'
param workload = 'swi'
param instance = '001'

param governanceTags = {
  owner: '<owner team>'
  costCentre: '<cost centre>'
  dataClassification: 'Internal'
  support: '<support group or email>'
}

param enableDeleteLock = true
param monthlyBudget = 300
param budgetStartDate = '2026-10-01T00:00:00Z'

param previewEnvironmentsEnabled = false

// Network: take the ranges from the APEX IP plan (these are placeholders)
param vnetAddressSpace = ['10.240.3.0/24']
param privateEndpointSubnetPrefix = '10.240.3.0/27'
param probeSubnetPrefix = '10.240.3.32/27'

// Resilience, fixed at creation. The probe environment has a zone setting; storage redundancy is below.
param probeZoneRedundancyEnabled = true
// param dnsServers = ['<hub DNS resolver IP>']
// param hubVirtualNetworkId = '<APEX hub VNet resource id>' // peering + DNS links so corporate users can reach the site

// File library (Blob storage). Replication and retention are fixed policy per environment.
param storageReplicationType = 'GZRS'
param softDeleteRetentionDays = 30
param malwareScanningEnabled = true // always on in prod; charged per GB scanned
param malwareScanCapGbPerMonth = 1000
param maxUploadMb = 100 // advice shown in the page, not enforced by Azure
param allowedExtensions = ['.pdf', '.docx', '.xlsx', '.pptx', '.csv', '.txt', '.png', '.jpg']
// param additionalSiteOrigins = ['https://files.example.com'] // custom domains the site is reached on

// Sign-in: only the Entra groups in ALLOWED_GROUP_IDS (deployment.env) can open the site and use the
// file library (read, upload, delete). The deploy script assigns them to the app registration too.
param allowedGroupIds = empty(readEnvironmentVariable('ALLOWED_GROUP_IDS', '')) ? [] : split(readEnvironmentVariable('ALLOWED_GROUP_IDS', ''), ',')
// Set by scripts/deploy.sh from the app registration it creates; never written here.
param entraClientId = readEnvironmentVariable('ENTRA_CLIENT_ID')
param entraClientSecret = readEnvironmentVariable('ENTRA_CLIENT_SECRET')

// Monitoring (one switch for all of it; always on in prod)
param enableMonitoring = true
param logRetentionDays = 180
param monitoringQueryFromInternet = true // false = dashboards and log queries only from the APEX network
param alertEmailReceivers = [
  // 'alerts@example.com'
]
param alertThresholds = {
  availabilityPercent: 95
}
param exportActivityLog = false
param enableServiceHealthAlert = true // false in all but one environment sharing a subscription

param monitoringViewerPrincipalIds = [
  // '<entra-group-object-id: service owners>'
]
param monitoringOperatorPrincipalIds = [
  // '<entra-group-object-id: operations>'
]

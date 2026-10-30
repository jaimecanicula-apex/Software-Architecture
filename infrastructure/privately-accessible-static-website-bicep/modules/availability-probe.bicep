// In-network availability probe for private sites. Internet web tests cannot
// reach a private endpoint, so a scheduled Container Apps job inside the VNet
// requests the site and records the result in Application Insights.
// No code package or storage account: the script is inlined from probe.sh.

param nameSuffix string
param location string
@description('Subnet delegated to Microsoft.App/environments (at least /27).')
param subnetId string
param logAnalyticsWorkspaceName string
param applicationInsightsName string
@description('Probe targets keyed by test name: url and expected HTTP status.')
param tests object
@description('Spread the probe\'s Container Apps environment across availability zones. Fixed at creation.')
param zoneRedundancyEnabled bool = false
@description('How often to probe (UTC cron).')
param cronExpression string = '*/5 * * * *'
@description('Any image with bash, curl and awk. Mirror it into an APEX registry for a fully private pull.')
param image string = 'mcr.microsoft.com/azure-cli:latest'
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource insights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${nameSuffix}'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: subnetId
      internal: true
    }
    zoneRedundant: zoneRedundancyEnabled
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
  }
}

resource probes 'Microsoft.App/jobs@2024-03-01' = [
  for test in items(tests): {
    name: take('caj-probe-${test.key}-${nameSuffix}', 32)
    location: location
    tags: tags
    properties: {
      environmentId: environment.id
      workloadProfileName: 'Consumption'
      configuration: {
        triggerType: 'Schedule'
        replicaTimeout: 120
        replicaRetryLimit: 0
        scheduleTriggerConfig: {
          cronExpression: cronExpression
          parallelism: 1
          replicaCompletionCount: 1
        }
        secrets: [
          {
            name: 'ai-connection-string'
            value: insights.properties.ConnectionString
          }
        ]
      }
      template: {
        containers: [
          {
            name: 'probe'
            image: image
            resources: {
              cpu: json('0.25')
              memory: '0.5Gi'
            }
            command: ['/bin/bash', '-c', loadTextContent('probe.sh')]
            env: [
              {
                name: 'TARGET_URL'
                value: test.value.url
              }
              {
                name: 'EXPECTED_STATUS'
                value: string(test.value.?expectedStatus ?? 200)
              }
              {
                name: 'TEST_NAME'
                value: test.key
              }
              {
                name: 'PROBE_LOCATION'
                value: 'vnet-${location}'
              }
              {
                name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
                secretRef: 'ai-connection-string'
              }
            ]
          }
        ]
      }
    }
  }
]

output testNames array = map(items(tests), test => test.key)

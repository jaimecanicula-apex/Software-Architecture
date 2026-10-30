// Monitoring for the private design: Log Analytics, workspace-based Application
// Insights (private ingestion), the Action Group, alert rules, the workbook
// dashboard and viewer/operator access. Front Door and internet web tests
// belong to the public designs and are not part of this one.

param location string
@description('Suffix used for alert and workbook names (for example swi-prod-weu-001).')
param nameSuffix string
param logAnalyticsName string
param applicationInsightsName string
param actionGroupName string
@description('Up to 12 characters; appears in SMS and email notifications.')
@maxLength(12)
param actionGroupShortName string
@description('Log Analytics retention (30-730 days).')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90
@description('Daily ingestion cap in GB; -1 for no cap.')
param logDailyQuotaGb int = -1
@description('Availability results sent by the in-network probe. Each gets an availability alert and a silence alert.')
param customAvailabilityTestNames array = []
@description('false: telemetry only arrives through the Azure Monitor Private Link Scope.')
param internetIngestionEnabled bool = false
@description('false: viewers must be on the APEX network to query logs and open the dashboard.')
param internetQueryEnabled bool = true
param alertEmailReceivers array = []
@secure()
@description('Webhooks (Teams, ITSM, PagerDuty...) keyed by name.')
param alertWebhookReceivers object = {}
param alertThresholds object = {}
@description('Alert on Azure incidents affecting the subscription. Enable it in only one environment per subscription.')
param serviceHealthAlertEnabled bool = true
@description('Entra ID object IDs (groups preferred) who can view the dashboard, logs, metrics and alerts.')
param viewerPrincipalIds array = []
@description('Entra ID object IDs who can also manage alerts, action groups and the workbook.')
param operatorPrincipalIds array = []
param tags object = {}

var availabilityPercent = alertThresholds.?availabilityPercent ?? 90

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    workspaceCapping: {
      dailyQuotaGb: logDailyQuotaGb
    }
    publicNetworkAccessForIngestion: internetIngestionEnabled ? 'Enabled' : 'Disabled'
    publicNetworkAccessForQuery: internetQueryEnabled ? 'Enabled' : 'Disabled'
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: internetIngestionEnabled ? 'Enabled' : 'Disabled'
    publicNetworkAccessForQuery: internetQueryEnabled ? 'Enabled' : 'Disabled'
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      for (address, i) in alertEmailReceivers: {
        name: 'email-${i}'
        emailAddress: address
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: [
      for hook in items(alertWebhookReceivers): {
        name: hook.key
        serviceUri: string(hook.value)
        useCommonAlertSchema: true
      }
    ]
  }
}

// ------------------------------------------------------------ alert rules
// Every rule notifies the Action Group; severity follows Azure Monitor (0 critical .. 4 verbose).

resource availabilityAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for name in customAvailabilityTestNames: {
    name: 'alert-availability-${name}-${nameSuffix}'
    location: 'global'
    tags: tags
    properties: {
      description: 'Availability test ${name} dropped below ${availabilityPercent}%.'
      severity: 1
      enabled: true
      scopes: [insights.id]
      evaluationFrequency: 'PT1M'
      windowSize: 'PT5M'
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [
          {
            criterionType: 'StaticThresholdCriterion'
            name: 'availability'
            metricNamespace: 'microsoft.insights/components'
            metricName: 'availabilityResults/availabilityPercentage'
            timeAggregation: 'Average'
            operator: 'LessThan'
            threshold: availabilityPercent
            dimensions: [
              {
                name: 'availabilityResult/name'
                operator: 'Include'
                values: [name]
              }
            ]
          }
        ]
      }
      actions: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
]

// A probe that stops reporting is an outage nobody would otherwise see.
resource probeSilentAlerts 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = [
  for name in customAvailabilityTestNames: {
    name: 'alert-probe-silent-${name}-${nameSuffix}'
    location: location
    tags: tags
    properties: {
      displayName: 'alert-probe-silent-${name}-${nameSuffix}'
      description: 'No availability result from the in-network probe ${name} for 15 minutes: the probe or the network path is down.'
      severity: 1
      enabled: true
      scopes: [workspace.id]
      evaluationFrequency: 'PT10M'
      windowSize: 'PT15M'
      criteria: {
        allOf: [
          {
            query: 'AppAvailabilityResults\n| where Name == "${name}"'
            timeAggregation: 'Count'
            operator: 'LessThan'
            threshold: 1
            failingPeriods: {
              minFailingPeriodsToAlert: 1
              numberOfEvaluationPeriods: 1
            }
          }
        ]
      }
      actions: {
        actionGroups: [actionGroup.id]
      }
    }
  }
]

// High-impact control-plane changes in the resource group.
var criticalOperations = {
  'static-web-app-deleted': 'Microsoft.Web/staticSites/delete'
  'front-door-deleted': 'Microsoft.Cdn/profiles/delete'
  'waf-policy-changed': 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies/write'
  'waf-policy-deleted': 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies/delete'
  'role-assignment-added': 'Microsoft.Authorization/roleAssignments/write'
  'lock-deleted': 'Microsoft.Authorization/locks/delete'
}

resource criticalChange 'Microsoft.Insights/activityLogAlerts@2020-10-01' = [
  for operation in items(criticalOperations): {
    name: 'alert-${operation.key}-${nameSuffix}'
    location: 'global'
    tags: tags
    properties: {
      description: 'Control-plane operation ${operation.value} ran in ${resourceGroup().name}.'
      enabled: true
      scopes: [resourceGroup().id]
      condition: {
        allOf: [
          {
            field: 'category'
            equals: 'Administrative'
          }
          {
            field: 'operationName'
            equals: operation.value
          }
        ]
      }
      actions: {
        actionGroups: [
          {
            actionGroupId: actionGroup.id
          }
        ]
      }
    }
  }
]

resource resourceHealth 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-resource-health-${nameSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'A resource in ${resourceGroup().name} became degraded or unavailable.'
    enabled: true
    scopes: [resourceGroup().id]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'properties.currentHealthStatus'
          containsAny: ['Degraded', 'Unavailable']
        }
        {
          field: 'properties.previousHealthStatus'
          containsAny: ['Available']
        }
        {
          field: 'properties.cause'
          containsAny: ['PlatformInitiated', 'Unknown']
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

resource serviceHealth 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (serviceHealthAlertEnabled) {
  name: 'alert-service-health-${nameSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Azure service incident, maintenance or security advisory affecting this subscription.'
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          anyOf: [
            {
              field: 'properties.incidentType'
              equals: 'Incident'
            }
            {
              field: 'properties.incidentType'
              equals: 'Maintenance'
            }
            {
              field: 'properties.incidentType'
              equals: 'Security'
            }
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// ------------------------------------------------------------ dashboard

var workbookQueries = [
  {
    name: 'availability'
    title: 'Availability by test (%)'
    viz: 'timechart'
    query: 'AppAvailabilityResults\n| summarize Availability = round(100.0 * countif(Success == true) / count(), 2) by bin(TimeGenerated, 1h), Name'
  }
  {
    name: 'availability-by-location'
    title: 'Availability by probe location'
    viz: 'table'
    query: 'AppAvailabilityResults\n| summarize Tests = count(), Failed = countif(Success == false), AvgDurationMs = round(avg(DurationMs), 0) by Location\n| order by Failed desc'
  }
  {
    name: 'alerts'
    title: 'Alerts fired'
    viz: 'table'
    query: 'AzureActivity\n| where CategoryValue == "Alert" or OperationNameValue has "alerts"\n| project TimeGenerated, OperationNameValue, ActivityStatusValue, ResourceGroup\n| top 50 by TimeGenerated'
  }
]

var workbook = {
  version: 'Notebook/1.0'
  items: concat(
    [
      {
        type: 1
        name: 'header'
        content: {
          json: '## Static website: ${nameSuffix}\nAvailability from the in-network probe, and alerts.'
        }
      }
      {
        type: 9
        name: 'parameters'
        content: {
          version: 'KqlParameterItem/1.0'
          style: 'pills'
          parameters: [
            {
              id: '7c1d8a4e-2f0b-4c56-9a53-0e2b1f6d3a10'
              version: 'KqlParameterItem/1.0'
              name: 'TimeRange'
              label: 'Time range'
              type: 4
              isRequired: true
              value: {
                durationMs: 86400000
              }
              typeSettings: {
                selectableValues: [
                  { durationMs: 3600000 }
                  { durationMs: 14400000 }
                  { durationMs: 86400000 }
                  { durationMs: 604800000 }
                  { durationMs: 2592000000 }
                ]
              }
            }
          ]
        }
      }
    ],
    map(workbookQueries, q => {
      type: 3
      name: q.name
      customWidth: '50'
      content: {
        version: 'KqlItem/1.0'
        title: q.title
        query: q.query
        size: 0
        timeContextFromParameter: 'TimeRange'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        crossComponentResources: [workspace.id]
        visualization: q.viz
      }
    })
  )
  fallbackResourceIds: [workspace.id]
  '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
}

resource dashboard 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('workbooks/static-website', nameSuffix)
  location: location
  kind: 'shared'
  tags: tags
  properties: {
    displayName: 'Static website - ${nameSuffix}'
    category: 'workbook'
    sourceId: workspace.id
    serializedData: string(workbook)
  }
}

// ------------------------------------------------------------ access
// Scoped to this environment's resource group only.
//   Viewers:   open the workbook, query logs, read metrics and alerts.
//   Operators: viewers + manage alert rules, action groups and workbooks.

var roleIds = {
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  monitoringReader: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  logAnalyticsReader: '73c42c96-874c-492b-b04d-ab87d138a893'
  monitoringContributor: '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
  workbookContributor: 'e8ddcd69-c73f-4f9f-9844-4100522f16ad'
}
var viewerRoles = [roleIds.reader, roleIds.monitoringReader, roleIds.logAnalyticsReader]
var operatorRoles = [roleIds.reader, roleIds.monitoringContributor, roleIds.logAnalyticsReader, roleIds.workbookContributor]

var roleAssignments = concat(
  flatten(map(viewerPrincipalIds, principal => map(viewerRoles, role => { key: 'viewer|${principal}|${role}', principalId: principal, roleId: role }))),
  flatten(map(operatorPrincipalIds, principal => map(operatorRoles, role => { key: 'operator|${principal}|${role}', principalId: principal, roleId: role })))
)

resource access 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for assignment in roleAssignments: {
    name: guid(resourceGroup().id, assignment.key)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', assignment.roleId)
      principalId: assignment.principalId
      description: 'Monitoring access for the static website (${nameSuffix}).'
    }
  }
]

output logAnalyticsWorkspaceId string = workspace.id
output logAnalyticsWorkspaceName string = workspace.name
output applicationInsightsId string = insights.id
output applicationInsightsName string = insights.name
output actionGroupId string = actionGroup.id
output workbookPortalUrl string = 'https://portal.azure.com/#@/resource${dashboard.id}/workbook'

// Observability foundation: Log Analytics, workspace-based Application Insights and the
// Action Group every alert notifies. Deployed first, because the Function, Front Door
// and storage send their telemetry here. Alerts and availability tests are in
// alerts.bicep, which needs the resources that send them.

param location string
param logAnalyticsName string
param applicationInsightsName string
param actionGroupName string
@description('At most 12 characters; shown in SMS and push notifications.')
param actionGroupShortName string
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90
@description('Daily ingestion cap in GB. -1 for no cap.')
param logDailyQuotaGb int = -1
param alertEmailReceivers array = []
@secure()
param alertWebhookReceivers object = {}
param tags object = {}

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
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
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
      for receiver in items(alertWebhookReceivers): {
        name: receiver.key
        serviceUri: string(receiver.value)
        useCommonAlertSchema: true
      }
    ]
  }
}

output logAnalyticsWorkspaceId string = workspace.id
output logAnalyticsWorkspaceName string = workspace.name
output applicationInsightsId string = insights.id
output applicationInsightsName string = insights.name
output applicationInsightsConnectionString string = insights.properties.ConnectionString
output actionGroupId string = actionGroup.id

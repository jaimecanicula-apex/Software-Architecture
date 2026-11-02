// Availability tests and alert rules. The site is public, so standard web tests run from
// Azure's test locations against the public URL; no in-VNet probe is needed.
//
// Every alert notifies the Action Group, which must have owned and tested recipients.

param location string
param nameSuffix string
param applicationInsightsId string
param actionGroupId string
param frontDoorProfileId string
param functionAppId string
@description('Full URLs to test, keyed by a short name: { home: \'https://...\', api: \'https://.../api/documents\' }.')
param availabilityUrls object
@description('Test frequency in seconds: 300, 600 or 900.')
@allowed([300, 600, 900])
param availabilityFrequencySeconds int = 300
@description('Front Door 5xx percentage that raises the alert.')
param frontDoor5xxPercentThreshold int = 5
@description('Front Door origin health percentage below which the alert is raised.')
param originHealthPercentThreshold int = 90
@description('Function HTTP 5xx count over the window that raises the alert.')
param function5xxCountThreshold int = 5
param tags object = {}

resource webTests 'Microsoft.Insights/webtests@2022-06-15' = [
  for test in items(availabilityUrls): {
    name: 'avail-${test.key}-${nameSuffix}'
    location: location
    kind: 'standard'
    tags: union(tags, { 'hidden-link:${applicationInsightsId}': 'Resource' })
    properties: {
      SyntheticMonitorId: 'avail-${test.key}-${nameSuffix}'
      Name: 'Availability ${test.key}'
      Enabled: true
      Frequency: availabilityFrequencySeconds
      Timeout: 30
      Kind: 'standard'
      RetryEnabled: true
      Locations: [
        { Id: 'emea-nl-ams-azr' }
        { Id: 'emea-gb-db3-azr' }
        { Id: 'emea-fr-pra-edge' }
      ]
      Request: {
        RequestUrl: string(test.value)
        HttpVerb: 'GET'
        ParseDependentRequests: false
      }
      ValidationRules: {
        ExpectedHttpStatusCode: 200
        SSLCheck: true
        SSLCertRemainingLifetimeCheck: 7
      }
    }
  }
]

resource availabilityAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for test in items(availabilityUrls): {
    name: 'alert-avail-${test.key}-${nameSuffix}'
    location: 'global'
    tags: union(tags, {
      'hidden-link:${resourceId('Microsoft.Insights/webtests', 'avail-${test.key}-${nameSuffix}')}': 'Resource'
      'hidden-link:${applicationInsightsId}': 'Resource'
    })
    properties: {
      description: 'Availability test "${test.key}" failed from at least two locations.'
      severity: 1
      enabled: true
      scopes: [resourceId('Microsoft.Insights/webtests', 'avail-${test.key}-${nameSuffix}'), applicationInsightsId]
      evaluationFrequency: 'PT5M'
      windowSize: 'PT15M'
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
        webTestId: resourceId('Microsoft.Insights/webtests', 'avail-${test.key}-${nameSuffix}')
        componentId: applicationInsightsId
        failedLocationCount: 2
      }
      actions: [
        { actionGroupId: actionGroupId }
      ]
    }
    dependsOn: [webTests]
  }
]

resource frontDoor5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-fd-5xx-${nameSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Front Door is returning 5xx responses.'
    severity: 2
    enabled: true
    scopes: [frontDoorProfileId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'fd5xx'
          metricName: 'Percentage5XX'
          operator: 'GreaterThan'
          threshold: frontDoor5xxPercentThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupId }
    ]
  }
}

resource originHealth 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-fd-origin-health-${nameSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'A Front Door origin (website or API) is unhealthy.'
    severity: 1
    enabled: true
    scopes: [frontDoorProfileId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'originHealth'
          metricName: 'OriginHealthPercentage'
          operator: 'LessThan'
          threshold: originHealthPercentThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupId }
    ]
  }
}

resource function5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-func-5xx-${nameSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'The document API is failing (HTTP 5xx), for example it cannot read storage.'
    severity: 2
    enabled: true
    scopes: [functionAppId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'func5xx'
          metricName: 'Http5xx'
          operator: 'GreaterThan'
          threshold: function5xxCountThreshold
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupId }
    ]
  }
}

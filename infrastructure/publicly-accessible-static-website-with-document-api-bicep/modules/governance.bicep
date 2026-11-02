// Delete lock and budget for the environment's resource group.

param environment string
param enableDeleteLock bool = false
param budgetName string
@description('Monthly cost budget for the resource group. 0 disables it.')
param monthlyBudget int = 0
param budgetStartDate string
param budgetContactEmails array = []
param actionGroupId string = ''
@description('Entra group object IDs that can see everything in the resource group (Reader).')
param viewerPrincipalIds array = []
@description('Entra group object IDs that can also manage alerts and monitoring (Reader and Monitoring Contributor).')
param operatorPrincipalIds array = []

var readerRole = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var monitoringContributorRole = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'

resource viewers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in union(viewerPrincipalIds, operatorPrincipalIds): {
    name: guid(resourceGroup().id, principalId, readerRole)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRole)
      principalId: principalId
      principalType: 'Group'
    }
  }
]

resource operators 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in operatorPrincipalIds: {
    name: guid(resourceGroup().id, principalId, monitoringContributorRole)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringContributorRole)
      principalId: principalId
      principalType: 'Group'
    }
  }
]

resource lock 'Microsoft.Authorization/locks@2020-05-01' = if (enableDeleteLock) {
  name: 'lock-cannot-delete'
  properties: {
    level: 'CanNotDelete'
    notes: 'Protects the ${environment} public static website with document API. Remove through change control only.'
  }
}

var contactGroups = empty(actionGroupId) ? [] : [actionGroupId]

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = if (monthlyBudget > 0) {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: monthlyBudget
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      Actual_GreaterThanOrEqualTo_80_Percent: {
        enabled: true
        threshold: 80
        thresholdType: 'Actual'
        operator: 'GreaterThanOrEqualTo'
        contactEmails: budgetContactEmails
        contactGroups: contactGroups
      }
      Forecasted_GreaterThanOrEqualTo_100_Percent: {
        enabled: true
        threshold: 100
        thresholdType: 'Forecasted'
        operator: 'GreaterThanOrEqualTo'
        contactEmails: budgetContactEmails
        contactGroups: contactGroups
      }
    }
  }
}

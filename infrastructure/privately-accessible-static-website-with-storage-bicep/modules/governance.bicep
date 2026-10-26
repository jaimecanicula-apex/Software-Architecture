// Delete lock and budget for the environment's resource group.

param environment string
param enableDeleteLock bool = false
param budgetName string
@description('Monthly cost budget for the resource group. 0 disables it.')
param monthlyBudget int = 0
param budgetStartDate string
param budgetContactEmails array = []
param actionGroupId string = ''

resource lock 'Microsoft.Authorization/locks@2020-05-01' = if (enableDeleteLock) {
  name: 'lock-cannot-delete'
  properties: {
    level: 'CanNotDelete'
    notes: 'Protects the ${environment} internal static website with storage. Remove through change control only.'
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

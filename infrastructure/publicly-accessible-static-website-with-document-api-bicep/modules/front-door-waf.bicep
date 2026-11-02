// Web Application Firewall policy for the Front Door profile. Prevention blocks;
// Detection only logs, which suits dev and qa while rules are tuned. Premium is
// required for the managed rule sets.

param name string
param location string = 'global'
@allowed(['Prevention', 'Detection'])
param mode string = 'Prevention'
param tags object = {}

resource policy 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: mode
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
        }
      ]
    }
  }
}

output id string = policy.id

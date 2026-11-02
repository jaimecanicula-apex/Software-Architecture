// The only public entry point. Premium is required for the managed WAF rule sets and
// for Private Link origins.
//
//   /api/*  --Private Link--> Function App (public access disabled; no caching)
//   /*      -----------------> Static Web App (accepts only this Front Door)
//
// The Private Link connection to the Function is created Pending. It must be approved
// on the Function before /api/* works: scripts/deploy.sh does that.

param profileName string
param endpointName string
param location string
param wafPolicyId string
param staticWebAppHostName string
param functionAppId string
param functionAppHostName string
@description('Optional custom domains. Each gets a managed certificate; validate the DNS TXT record it shows.')
param customDomains array = []
param logAnalyticsWorkspaceId string = ''
param tags object = {}

resource profile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: profile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource domains 'Microsoft.Cdn/profiles/customDomains@2024-02-01' = [
  for host in customDomains: {
    parent: profile
    name: replace(host, '.', '-')
    properties: {
      hostName: host
      tlsSettings: {
        certificateType: 'ManagedCertificate'
        minimumTlsVersion: 'TLS12'
      }
    }
  }
]

// ---------------------------------------------------------------- origins

resource webGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: profile
  name: 'og-web'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

resource webOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: webGroup
  name: 'origin-swa'
  properties: {
    hostName: staticWebAppHostName
    originHostHeader: staticWebAppHostName
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource apiGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: profile
  name: 'og-api'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/api/documents'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

resource apiOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: apiGroup
  name: 'origin-func'
  properties: {
    hostName: functionAppHostName
    originHostHeader: functionAppHostName
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: {
      privateLink: {
        id: functionAppId
      }
      groupId: 'sites'
      privateLinkLocation: location
      requestMessage: 'Front Door private access to the Function App'
    }
  }
}

// ---------------------------------------------------------------- routes

var customDomainRefs = [for (host, i) in customDomains: { id: domains[i].id }]
var routeDomains = concat([{ id: endpoint.id }], customDomainRefs)

// /api/* is listed first and is more specific. No cacheConfiguration means no caching,
// so a published or withdrawn document shows immediately.
resource apiRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'route-api'
  properties: {
    originGroup: {
      id: apiGroup.id
    }
    patternsToMatch: ['/api/*']
    supportedProtocols: ['Http', 'Https']
    httpsRedirect: 'Enabled'
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    customDomains: customDomainRefs
    enabledState: 'Enabled'
  }
  dependsOn: [apiOrigin]
}

resource webRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'route-web'
  properties: {
    originGroup: {
      id: webGroup.id
    }
    patternsToMatch: ['/*']
    supportedProtocols: ['Http', 'Https']
    httpsRedirect: 'Enabled'
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    customDomains: customDomainRefs
    enabledState: 'Enabled'
  }
  dependsOn: [webOrigin, apiRoute]
}

// ---------------------------------------------------------------- WAF

resource security 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: profile
  name: 'secp-waf'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: routeDomains
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-front-door'
  scope: profile
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'FrontDoorAccessLog', enabled: true }
      { category: 'FrontDoorHealthProbeLog', enabled: true }
      { category: 'FrontDoorWebApplicationFirewallLog', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output profileId string = profile.id
output profileName string = profile.name
@description('The value Static Web Apps must require in the X-Azure-FDID header.')
output frontDoorId string = profile.properties.frontDoorId
output endpointHostName string = endpoint.properties.hostName
output customDomainValidation array = [for (host, i) in customDomains: {
  hostName: host
  validationToken: domains[i].properties.validationProperties.validationToken
}]

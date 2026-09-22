@description('Azure region for API Management')
param location string

@description('Globally unique API Management service name')
param apimName string

@description('API Management publisher name')
param publisherName string

@description('API Management publisher email address')
param publisherEmail string

@description('Microsoft Entra tenant ID')
param tenantId string

@description('SPA application client ID allowed to call the Responses API')
param spaClientId string

@description('Confidential OAuth client ID used by the Foundry MCP connection')
param apiClientId string

@description('Allowed browser origins')
param allowedWebOrigins array

@description('Foundry Responses backend URL')
param foundryResponsesUrl string

@description('Azure MCP Container App backend URL')
param mcpBackendUrl string

@description('Azure MCP resource application client ID')
param mcpClientId string

@secure()
@description('Application Insights instrumentation key for APIM diagnostics')
param appInsightsInstrumentationKey string

@description('Application Insights resource ID for APIM diagnostics')
param appInsightsResourceId string

assert publisherNameIsRequired = !empty(trim(publisherName))
assert publisherEmailIsRequired = !empty(trim(publisherEmail)) && contains(publisherEmail, '@')
assert spaClientIdIsRequired = !empty(trim(spaClientId))
assert apiClientIdIsRequired = !empty(trim(apiClientId))
assert webOriginsAreRequired = length(allowedWebOrigins) > 0 && !contains(allowedWebOrigins, '')
assert mcpClientIdIsRequired = !empty(trim(mcpClientId))

var allowedOriginElements = [
  for origin in allowedWebOrigins: '<origin>${trim(string(origin))}</origin>'
]
var allowedOriginsXml = join(allowedOriginElements, '')

var responsesPolicy = replace(
  replace(
    replace(
      loadTextContent('policies/responses.xml'),
      '__ALLOWED_ORIGINS__',
      allowedOriginsXml
    ),
    '__TENANT_ID__',
    tenantId
  ),
  '__SPA_CLIENT_ID__',
  spaClientId
)

var mcpPolicy = replace(
  replace(
    replace(
      loadTextContent('policies/mcp.xml'),
      '__TENANT_ID__',
      tenantId
    ),
    '__MCP_CLIENT_ID__',
    mcpClientId
  ),
  '__API_CLIENT_ID__',
  apiClientId
)

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
    }
    developerPortalStatus: 'Disabled'
    legacyPortalStatus: 'Disabled'
    natGatewayState: 'Enabled'
    publisherName: publisherName
    publisherEmail: publisherEmail
    publicNetworkAccess: 'Enabled'
  }
}

resource appInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'application-insights'
  properties: {
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    description: 'Application Insights logger for APIM gateway telemetry'
    isBuffered: true
    loggerType: 'applicationInsights'
    resourceId: appInsightsResourceId
  }
}

resource appInsightsDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    backend: {
      request: {
        body: {
          bytes: 8192
        }
        headers: []
      }
      response: {
        body: {
          bytes: 8192
        }
        headers: []
      }
    }
    frontend: {
      request: {
        body: {
          bytes: 8192
        }
        headers: []
      }
      response: {
        body: {
          bytes: 8192
        }
        headers: []
      }
    }
    httpCorrelationProtocol: 'W3C'
    logClientIp: false
    loggerId: appInsightsLogger.id
    metrics: true
    operationNameFormat: 'Name'
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
    verbosity: 'information'
  }
}

resource foundryBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'foundry-responses'
  properties: {
    protocol: 'http'
    url: foundryResponsesUrl
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource mcpBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'azure-mcp'
  properties: {
    protocol: 'http'
    url: mcpBackendUrl
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource responsesApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'agent-responses'
  properties: {
    displayName: 'User Passthrough Agent Responses'
    path: 'agent'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
  }
}

resource responsesOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: responsesApi
  name: 'post-agent-responses'
  properties: {
    displayName: 'Create agent response'
    method: 'POST'
    urlTemplate: '/responses'
  }
}

resource responsesOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: responsesOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: responsesPolicy
  }
  dependsOn: [
    foundryBackend
  ]
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'user-passthrough-mcp'
  properties: {
    type: 'mcp'
    apiType: 'mcp'
    displayName: 'User Passthrough MCP'
    path: 'mcp/user-passthrough'
    protocols: [
      'https'
    ]
    serviceUrl: mcpBackendUrl
    subscriptionRequired: false
    mcpProperties: {
      transportType: 'streamable'
      endpoints: {
        mcp: {
          uriTemplate: '/'
        }
      }
    }
  }
}

resource mcpApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: mcpApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: mcpPolicy
  }
  dependsOn: [
    mcpBackend
  ]
}

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: 'agent-and-mcp-test'
  properties: {
    displayName: 'Agent Responses Test'
    description: 'Test product for the user-passthrough Responses API'
    approvalRequired: false
    state: 'published'
    subscriptionRequired: true
  }
}

resource responsesProductAssociation 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: responsesApi.name
}

resource testSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'user-passthrough-test'
  properties: {
    displayName: 'User Passthrough Test'
    scope: product.id
    state: 'active'
    allowTracing: false
  }
}

output serviceName string = apim.name
output serviceId string = apim.id
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
output responsesEndpoint string = '${apim.properties.gatewayUrl}/agent/responses'
output mcpEndpoint string = '${apim.properties.gatewayUrl}/mcp/user-passthrough/mcp'
output productId string = product.id
output subscriptionId string = testSubscription.id

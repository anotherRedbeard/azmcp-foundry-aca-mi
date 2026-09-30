@description('Location for all resources')
param location string = resourceGroup().location

@description('Name for the Azure Container App')
param acaName string

@description('Client ID of the manually created Entra application protecting Azure MCP')
param mcpAppClientId string

@description('Object ID of the MCP application service principal')
param mcpAppServicePrincipalObjectId string

@description('Application ID URI of the MCP application')
param mcpAppIdentifierUri string

@description('Delegated permission scope ID for Mcp.Tools.ReadWrite')
param mcpAppScopeId string

@description('API Management service name. Leave empty to generate a stable name.')
param apimName string = ''

@description('Microsoft Foundry account name. Leave empty to generate a stable name.')
param foundryAccountName string = ''

@description('Microsoft Foundry project name')
param foundryProjectName string = 'user-passthrough'

@description('API Management publisher name')
param apimPublisherName string = ''

@description('API Management publisher email')
param apimPublisherEmail string = ''

@description('SPA client ID allowed to call the Responses API')
param spaClientId string = ''

@description('Confidential API client ID used by the Foundry OAuth2 MCP connection')
param apiClientId string = ''

@description('gpt-5 deployment name')
param gpt5DeploymentName string = 'gpt-5'

@description('gpt-5 model name')
param gpt5ModelName string = 'gpt-5'

@description('gpt-5 model version')
param gpt5ModelVersion string = '2025-08-07'

@description('gpt-5 deployment SKU')
param gpt5SkuName string = 'GlobalStandard'

@description('gpt-5 deployment capacity in thousands of tokens per minute')
param gpt5Capacity int = 200

@description('gpt-5-mini deployment name')
param gpt5MiniDeploymentName string = 'gpt-5-mini'

@description('gpt-5-mini model name')
param gpt5MiniModelName string = 'gpt-5-mini'

@description('gpt-5-mini model version')
param gpt5MiniModelVersion string = '2025-08-07'

@description('gpt-5-mini deployment SKU')
param gpt5MiniSkuName string = 'GlobalStandard'

@description('gpt-5-mini deployment capacity in thousands of tokens per minute')
param gpt5MiniCapacity int = 200

var resolvedApimName = !empty(apimName)
  ? apimName
  : 'apim-${uniqueString(subscription().id, resourceGroup().id, acaName)}-obo'
var resolvedFoundryAccountName = !empty(foundryAccountName)
  ? foundryAccountName
  : 'aif-${uniqueString(subscription().id, resourceGroup().id, acaName)}-obo'

var appInsightsName = '${acaName}-insights'
module appInsights 'modules/application-insights.bicep' = {
  name: 'application-insights-deployment'
  params: {
    name: appInsightsName
    location: location
  }
}

module foundry 'modules/foundry.bicep' = {
  name: 'foundry-deployment'
  params: {
    location: location
    accountName: resolvedFoundryAccountName
    projectName: foundryProjectName
    gpt5DeploymentName: gpt5DeploymentName
    gpt5ModelName: gpt5ModelName
    gpt5ModelVersion: gpt5ModelVersion
    gpt5SkuName: gpt5SkuName
    gpt5Capacity: gpt5Capacity
    gpt5MiniDeploymentName: gpt5MiniDeploymentName
    gpt5MiniModelName: gpt5MiniModelName
    gpt5MiniModelVersion: gpt5MiniModelVersion
    gpt5MiniSkuName: gpt5MiniSkuName
    gpt5MiniCapacity: gpt5MiniCapacity
  }
}

var tokenExchangeAudience = environment().name == 'AzureUSGovernment'
  ? 'api://AzureADTokenExchangeUSGov'
  : environment().name == 'AzureChinaCloud'
    ? 'api://AzureADTokenExchangeChina'
    : 'api://AzureADTokenExchange'

module acaManagedIdentity 'modules/aca-user-assigned-identity.bicep' = {
  name: 'aca-user-assigned-identity-deployment'
  params: {
    location: location
    name: '${acaName}-obo-identity'
  }
}

module acaInfrastructure 'modules/aca-infrastructure.bicep' = {
  name: 'aca-infrastructure-deployment'
  params: {
    name: acaName
    location: location
    appInsightsConnectionString: appInsights.outputs.connectionString
    azureMcpCollectTelemetry: string(!empty(appInsights.outputs.connectionString))
    logAnalyticsCustomerId: appInsights.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: appInsights.outputs.logAnalyticsSharedKey
    azureAdTenantId: tenant().tenantId
    azureAdClientId: mcpAppClientId
    userAssignedManagedIdentityId: acaManagedIdentity.outputs.resourceId
    userAssignedManagedIdentityClientId: acaManagedIdentity.outputs.clientId
    tokenExchangeAudience: tokenExchangeAudience
    namespaces: [
      'storage'
      'subscription'
      'group'
      'arm'
    ]
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    apimName: resolvedApimName
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    tenantId: tenant().tenantId
    spaClientId: spaClientId
    apiClientId: apiClientId
    foundryResponsesUrl: '${foundry.outputs.projectEndpoint}/openai/v1'
    mcpBackendUrl: acaInfrastructure.outputs.containerAppUrl
    mcpClientId: mcpAppClientId
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
    appInsightsResourceId: appInsights.outputs.resourceId
  }
}

output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AZURE_LOCATION string = location
output SPA_CLIENT_ID string = spaClientId
output API_CLIENT_ID string = apiClientId
output FOUNDRY_API_SCOPE string = 'https://ai.azure.com/user_impersonation'

output ENTRA_APP_CLIENT_ID string = mcpAppClientId
output ENTRA_APP_SERVICE_PRINCIPAL_ID string = mcpAppServicePrincipalObjectId
output ENTRA_APP_IDENTIFIER_URI string = mcpAppIdentifierUri
output ENTRA_APP_SCOPE_ID string = mcpAppScopeId
output ENTRA_APP_SCOPE_VALUE string = 'Mcp.Tools.ReadWrite'

output CONTAINER_APP_URL string = acaInfrastructure.outputs.containerAppUrl
output CONTAINER_APP_NAME string = acaInfrastructure.outputs.containerAppName
output CONTAINER_APP_PRINCIPAL_ID string = acaManagedIdentity.outputs.principalId
output CONTAINER_APP_MANAGED_IDENTITY_CLIENT_ID string = acaManagedIdentity.outputs.clientId
output AZURE_CONTAINER_APP_ENVIRONMENT_ID string = acaInfrastructure.outputs.containerAppEnvironmentId

output APIM_NAME string = apim.outputs.serviceName
output APIM_GATEWAY_URL string = apim.outputs.gatewayUrl
output APIM_PRINCIPAL_ID string = apim.outputs.principalId
output RESPONSES_API_URL string = apim.outputs.responsesEndpoint
output MCP_API_URL string = apim.outputs.mcpEndpoint
output APIM_PRODUCT_ID string = apim.outputs.productId
output APIM_TEST_SUBSCRIPTION_ID string = apim.outputs.subscriptionId

output AZURE_AI_ACCOUNT_NAME string = foundry.outputs.accountName
output AZURE_AI_ACCOUNT_ID string = foundry.outputs.accountId
output AZURE_AI_ACCOUNT_ENDPOINT string = foundry.outputs.accountEndpoint
output AZURE_AI_PROJECT_NAME string = foundry.outputs.projectName
output AZURE_AI_PROJECT_ID string = foundry.outputs.projectId
output AZURE_AI_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
output AZURE_AI_PROJECT_PRINCIPAL_ID string = foundry.outputs.projectPrincipalId
output AZURE_AI_GPT5_DEPLOYMENT_NAME string = foundry.outputs.gpt5DeploymentName
output AZURE_AI_GPT5_MINI_DEPLOYMENT_NAME string = foundry.outputs.gpt5MiniDeploymentName
output APPLICATION_INSIGHTS_NAME string = appInsightsName

@description('Existing API Management service name')
param apimName string

@description('Microsoft Entra tenant ID')
param tenantId string

@description('Azure MCP resource application client ID')
param mcpClientId string

@description('Confidential OAuth client ID used by the Foundry MCP connection')
param apiClientId string

@description('Optional approved ChatGPT OAuth client ID. Leave empty until the client is registered.')
@maxLength(36)
param chatGptClientId string = ''

var chatGptClientIdHasGuidShape = length(chatGptClientId) == 36
  ? substring(chatGptClientId, 8, 1) == '-' && substring(chatGptClientId, 13, 1) == '-' && substring(
      chatGptClientId,
      18,
      1
    ) == '-' && substring(chatGptClientId, 23, 1) == '-' && length(replace(chatGptClientId, '-', '')) == 32
  : false
var chatGptClientIdCharactersAreValid = empty(filter(
  range(0, length(chatGptClientId)),
  index => !contains('0123456789abcdef-', toLower(substring(chatGptClientId, index, 1)))
))
assert chatGptClientIdIsValid = empty(chatGptClientId) || (chatGptClientIdHasGuidShape && chatGptClientIdCharactersAreValid)

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' existing = {
  parent: apim
  name: 'user-passthrough-mcp'
}

var resourcePath = '/mcp/user-passthrough/mcp'
var resourceUrl = '${apim.properties.gatewayUrl}${resourcePath}'
var metadataUrl = '${apim.properties.gatewayUrl}/.well-known/oauth-protected-resource${resourcePath}'
var scopeUri = '${resourceUrl}/Mcp.Tools.ReadWrite'
var chatGptClientClaim = empty(chatGptClientId) ? '' : '<value>${toLower(chatGptClientId)}</value>'

var authenticatedPolicy = replace(
  replace(
    replace(replace(loadTextContent('policies/mcp.xml'), '__TENANT_ID__', tenantId), '__MCP_CLIENT_ID__', mcpClientId),
    '__API_CLIENT_ID__',
    apiClientId
  ),
  '__CHATGPT_CLIENT_CLAIM__',
  chatGptClientClaim
)

var mcpPolicy = replace(replace(authenticatedPolicy, '__METADATA_URL__', metadataUrl), '__SCOPE_URI__', scopeUri)

var metadataPolicy = replace(
  replace(
    replace(loadTextContent('policies/mcp-metadata.xml'), '__RESOURCE_URL__', resourceUrl),
    '__TENANT_ID__',
    tenantId
  ),
  '__SCOPE_URI__',
  scopeUri
)

resource metadataApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'user-passthrough-mcp-metadata'
  properties: {
    displayName: 'User Passthrough MCP Protected Resource Metadata'
    path: '.well-known/oauth-protected-resource'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource metadataOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: metadataApi
  name: 'get-user-passthrough-mcp-metadata'
  properties: {
    displayName: 'Get Azure MCP protected resource metadata'
    method: 'GET'
    urlTemplate: resourcePath
  }
}

resource metadataOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: metadataOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: metadataPolicy
  }
}

resource mcpApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: mcpApi
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: mcpPolicy
  }
}

output protectedResourceMetadataUrl string = metadataUrl
output scope string = scopeUri

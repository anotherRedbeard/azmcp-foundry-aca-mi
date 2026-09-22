@description('Azure region for the Foundry resources')
param location string

@description('Globally unique Microsoft Foundry account name')
param accountName string

@description('Microsoft Foundry project name')
param projectName string

@description('Deployment name for gpt-5')
param gpt5DeploymentName string = 'gpt-5'

@description('Model name for the gpt-5 deployment')
param gpt5ModelName string = 'gpt-5'

@description('Model version for the gpt-5 deployment')
param gpt5ModelVersion string = '2025-08-07'

@description('SKU for the gpt-5 deployment')
param gpt5SkuName string = 'GlobalStandard'

@description('Capacity in thousands of tokens per minute for the gpt-5 deployment')
@minValue(1)
param gpt5Capacity int = 200

@description('Deployment name for gpt-5-mini')
param gpt5MiniDeploymentName string = 'gpt-5-mini'

@description('Model name for the gpt-5-mini deployment')
param gpt5MiniModelName string = 'gpt-5-mini'

@description('Model version for the gpt-5-mini deployment')
param gpt5MiniModelVersion string = '2025-08-07'

@description('SKU for the gpt-5-mini deployment')
param gpt5MiniSkuName string = 'GlobalStandard'

@description('Capacity in thousands of tokens per minute for the gpt-5-mini deployment')
@minValue(1)
param gpt5MiniCapacity int = 200

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectName
    description: 'Foundry project for the user-passthrough Azure MCP variant'
  }
}

resource gpt5Deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: gpt5DeploymentName
  dependsOn: [
    gpt5MiniDeployment
  ]
  sku: {
    name: gpt5SkuName
    capacity: gpt5Capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: gpt5ModelName
      version: gpt5ModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource gpt5MiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: account
  name: gpt5MiniDeploymentName
  dependsOn: [
    project
  ]
  sku: {
    name: gpt5MiniSkuName
    capacity: gpt5MiniCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: gpt5MiniModelName
      version: gpt5MiniModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

output accountName string = account.name
output accountId string = account.id
output accountEndpoint string = account.properties.endpoint
output accountPrincipalId string = account.identity.principalId
output projectName string = project.name
output projectId string = project.id
output projectEndpoint string = 'https://${account.name}.services.ai.azure.com/api/projects/${project.name}'
output projectPrincipalId string = project.identity.principalId
output gpt5DeploymentName string = gpt5Deployment.name
output gpt5MiniDeploymentName string = gpt5MiniDeployment.name

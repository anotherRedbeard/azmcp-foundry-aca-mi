targetScope = 'subscription'

@description('Azure region for the resource group and all web-host resources.')
param location string = 'eastus2'

@description('Naming prefix for the web-host resources.')
param namingPrefix string = 'azmcp-webapps-dev'

@description('Resource group for the shared web-host resources.')
param resourceGroupName string = 'rg-${namingPrefix}'

@description('Azure Container Apps environment name.')
param environmentName string = 'cae-${namingPrefix}'

@description('Log Analytics workspace name.')
param logAnalyticsName string = 'log-${namingPrefix}'

@description('User-assigned identity used only to pull images from ACR.')
param pullIdentityName string = 'id-${namingPrefix}-acr-pull'

@description('Globally unique Azure Container Registry name.')
param registryName string = 'acr${replace(toLower(namingPrefix), '-', '')}${uniqueString(subscription().id, namingPrefix)}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    product: 'azmcp'
    purpose: 'dual-web-host'
  }
}

module foundationResources 'foundation-resources.bicep' = {
  name: 'web-host-foundation'
  scope: resourceGroup
  params: {
    location: location
    environmentName: environmentName
    logAnalyticsName: logAnalyticsName
    pullIdentityName: pullIdentityName
    registryName: registryName
  }
}

output resourceGroupName string = resourceGroup.name
output environmentName string = foundationResources.outputs.environmentName
output registryName string = foundationResources.outputs.registryName
output registryLoginServer string = foundationResources.outputs.registryLoginServer
output pullIdentityName string = foundationResources.outputs.pullIdentityName

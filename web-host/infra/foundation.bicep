targetScope = 'subscription'

@description('Azure region for the resource group and web-host resources.')
param location string = 'eastus2'

@description('Naming prefix for the web-host resources.')
param namingPrefix string = 'azmcp-webapps-dev'

@description('Resource group for the web-host resources.')
param resourceGroupName string = 'rg-${namingPrefix}'

@description('Azure Container Apps environment name.')
param environmentName string = 'cae-${namingPrefix}-private'

@description('Virtual network name for the web-host environment.')
param virtualNetworkName string = 'vnet-${namingPrefix}'

@description('Virtual network address prefix.')
param virtualNetworkAddressPrefix string = '10.30.0.0/16'

@description('Dedicated Container Apps infrastructure subnet name.')
param containerAppsSubnetName string = 'snet-container-apps'

@description('Dedicated Container Apps infrastructure subnet prefix.')
param containerAppsSubnetPrefix string = '10.30.0.0/24'

@description('Private endpoint subnet name.')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('Private endpoint subnet prefix.')
param privateEndpointSubnetPrefix string = '10.30.1.0/27'

@description('Private DNS zone for Cosmos DB for NoSQL.')
param cosmosPrivateDnsZoneName string = 'privatelink.documents.azure.com'

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
    purpose: 'web-host'
  }
}

module foundationResources 'foundation-resources.bicep' = {
  name: 'web-host-foundation'
  scope: resourceGroup
  params: {
    location: location
    environmentName: environmentName
    virtualNetworkName: virtualNetworkName
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    containerAppsSubnetName: containerAppsSubnetName
    containerAppsSubnetPrefix: containerAppsSubnetPrefix
    privateEndpointSubnetName: privateEndpointSubnetName
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    cosmosPrivateDnsZoneName: cosmosPrivateDnsZoneName
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
output virtualNetworkName string = foundationResources.outputs.virtualNetworkName
output privateEndpointSubnetId string = foundationResources.outputs.privateEndpointSubnetId
output cosmosPrivateDnsZoneId string = foundationResources.outputs.cosmosPrivateDnsZoneId

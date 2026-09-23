targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Azure Container Apps environment name.')
param environmentName string

@description('Log Analytics workspace name.')
param logAnalyticsName string

@description('User-assigned identity used only to pull images from ACR.')
param pullIdentityName string

@description('Azure Container Registry name.')
param registryName string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: pullIdentityName
  location: location
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, pullIdentity.id, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    principalId: pullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

output environmentName string = containerAppsEnvironment.name
output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
output pullIdentityName string = pullIdentity.name

targetScope = 'resourceGroup'

@description('Azure region for the Container App.')
param location string = resourceGroup().location

@description('Existing Azure Container Apps environment name.')
param environmentName string

@description('Existing Azure Container Registry name.')
param registryName string

@description('Existing user-assigned identity used to pull images from ACR.')
param pullIdentityName string

@description('Resource ID of the subnet used for private endpoints.')
param privateEndpointSubnetId string

@description('Resource ID of the Cosmos DB private DNS zone.')
param cosmosPrivateDnsZoneId string

@description('User-passthrough web Container App name.')
param appName string = 'ca-azmcp-user-passthrough'

@description('Fully qualified user-passthrough web application image.')
param image string

@description('Microsoft Entra tenant ID.')
param entraTenantId string

@description('User-passthrough SPA application client ID.')
param spaClientId string

@description('Microsoft Foundry delegated scope requested by the SPA.')
param foundryApiScope string = 'https://ai.azure.com/user_impersonation'

@description('User-passthrough APIM Responses endpoint.')
param apimResponsesUrl string

@secure()
@description('User-passthrough APIM subscription key.')
param apimSubscriptionKey string

@description('Cosmos DB for NoSQL account name used for chat history.')
param cosmosAccountName string = 'cosmos-${uniqueString(subscription().id, resourceGroup().id, 'ca-azmcp-user-passthrough')}'

@description('Cosmos DB database name used for chat history.')
param cosmosDatabaseName string = 'chat-history'

@description('Cosmos DB container name used for chat history.')
param cosmosContainerName string = 'conversations'

@description('Tags applied to the Cosmos DB account. Existing deployments should pass their current tags so environment-specific governance tags are preserved.')
param cosmosTags object = {
  product: 'azmcp'
  identityModel: 'user-passthrough'
  workload: 'chat-history'
}

@allowed([
  'Disabled'
  'Enabled'
])
@description('Cosmos public network access. Keep Disabled for normal deployments; Enabled is only for a temporary parallel migration.')
param cosmosPublicNetworkAccess string = 'Disabled'

var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'
var cosmosContainerDataScope = '${cosmosAccount.id}/dbs/${cosmosDatabaseName}/colls/${cosmosContainerName}'

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: pullIdentityName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: cosmosTags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    enableAutomaticFailover: true
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: cosmosPublicNetworkAccess
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/userId'
        ]
        kind: 'Hash'
        version: 2
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/content/?'
          }
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pep-${cosmosAccount.name}'
  location: location
  tags: {
    product: 'azmcp'
    identityModel: 'user-passthrough'
    workload: 'chat-history'
  }
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmos-sql'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource cosmosPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: cosmosPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos-sql'
        properties: {
          privateDnsZoneId: cosmosPrivateDnsZoneId
        }
      }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: {
    product: 'azmcp'
    identityModel: 'user-passthrough'
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${pullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: 1
      ingress: {
        external: true
        targetPort: 3000
        allowInsecure: false
        transport: 'auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: pullIdentity.id
        }
      ]
      secrets: [
        {
          name: 'apim-subscription-key'
          value: apimSubscriptionKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'user-passthrough-web'
          image: image
          env: [
            {
              name: 'PORT'
              value: '3000'
            }
            {
              name: 'ENTRA_TENANT_ID'
              value: entraTenantId
            }
            {
              name: 'ENTRA_SPA_CLIENT_ID'
              value: spaClientId
            }
            {
              name: 'FOUNDRY_API_SCOPE'
              value: foundryApiScope
            }
            {
              name: 'APIM_RESPONSES_URL'
              value: apimResponsesUrl
            }
            {
              name: 'APIM_SUBSCRIPTION_KEY'
              secretRef: 'apim-subscription-key'
            }
            {
              name: 'AZURE_HOSTED'
              value: 'true'
            }
            {
              name: 'CHAT_HISTORY_BACKEND'
              value: 'cosmos'
            }
            {
              name: 'COSMOS_ENDPOINT'
              value: cosmosAccount.properties.documentEndpoint
            }
            {
              name: 'COSMOS_DATABASE_NAME'
              value: cosmosDatabaseName
            }
            {
              name: 'COSMOS_CONTAINER_NAME'
              value: cosmosContainerName
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 3000
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

resource cosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, app.id, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: app.identity.principalId
    scope: cosmosContainerDataScope
  }
}

output appName string = app.name
output appUrl string = 'https://${app.properties.configuration.ingress.fqdn}'
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosPrivateEndpointName string = cosmosPrivateEndpoint.name

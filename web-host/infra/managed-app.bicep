targetScope = 'resourceGroup'

@description('Azure region for the Container App.')
param location string = resourceGroup().location

@description('Existing Azure Container Apps environment name.')
param environmentName string

@description('Existing Azure Container Registry name.')
param registryName string

@description('Existing user-assigned identity used to pull images from ACR.')
param pullIdentityName string

@description('Managed-identity web Container App name.')
param appName string = 'ca-azmcp-managed-identity'

@description('Fully qualified managed-identity web application image.')
param image string

@description('Microsoft Entra tenant ID.')
param entraTenantId string

@description('Managed-identity SPA application client ID.')
param spaClientId string

@description('Managed-identity protected API delegated scope.')
param apiScope string

@description('Managed-identity APIM Responses endpoint.')
param apimResponsesUrl string

@secure()
@description('Managed-identity APIM subscription key. Replace the placeholder after deployment.')
param apimSubscriptionKey string

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: pullIdentityName
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: {
    product: 'azmcp'
    identityModel: 'managed-identity'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${pullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
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
          name: 'managed-identity-web'
          image: image
          env: [
            {
              name: 'PORT'
              value: '3000'
            }
            {
              name: 'NODE_ENV'
              value: 'production'
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
              name: 'ENTRA_API_SCOPE'
              value: apiScope
            }
            {
              name: 'APIM_RESPONSES_URL'
              value: apimResponsesUrl
            }
            {
              name: 'APIM_SUBSCRIPTION_KEY'
              secretRef: 'apim-subscription-key'
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

output appName string = app.name
output appUrl string = 'https://${app.properties.configuration.ingress.fqdn}'

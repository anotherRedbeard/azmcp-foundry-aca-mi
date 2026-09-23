targetScope = 'resourceGroup'

@description('Azure region for both Container Apps.')
param location string = resourceGroup().location

@description('Existing Azure Container Apps environment name.')
param environmentName string

@description('Existing Azure Container Registry name.')
param registryName string

@description('Existing user-assigned identity used to pull images from ACR.')
param pullIdentityName string

@description('Managed-identity web Container App name.')
param managedAppName string = 'ca-azmcp-managed-identity'

@description('User-passthrough web Container App name.')
param passthroughAppName string = 'ca-azmcp-user-passthrough'

@description('Fully qualified managed-identity web application image.')
param managedImage string

@description('Fully qualified user-passthrough web application image.')
param passthroughImage string

@description('Microsoft Entra tenant ID used by both web applications.')
param entraTenantId string

@description('Managed-identity SPA application client ID.')
param managedSpaClientId string

@description('Managed-identity protected API delegated scope.')
param managedApiScope string

@description('Managed-identity APIM Responses endpoint.')
param managedApimResponsesUrl string

@secure()
@description('Managed-identity APIM subscription key.')
param managedApimSubscriptionKey string

@description('User-passthrough SPA application client ID.')
param passthroughSpaClientId string

@description('Microsoft Foundry delegated scope requested by the passthrough SPA.')
param passthroughFoundryApiScope string

@description('User-passthrough APIM Responses endpoint.')
param passthroughApimResponsesUrl string

@secure()
@description('User-passthrough APIM subscription key.')
param passthroughApimSubscriptionKey string

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: pullIdentityName
}

resource managedApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: managedAppName
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
          value: managedApimSubscriptionKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'managed-identity-web'
          image: managedImage
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
              value: managedSpaClientId
            }
            {
              name: 'ENTRA_API_SCOPE'
              value: managedApiScope
            }
            {
              name: 'APIM_RESPONSES_URL'
              value: managedApimResponsesUrl
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

resource passthroughApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: passthroughAppName
  location: location
  tags: {
    product: 'azmcp'
    identityModel: 'user-passthrough'
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
          value: passthroughApimSubscriptionKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'user-passthrough-web'
          image: passthroughImage
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
              value: passthroughSpaClientId
            }
            {
              name: 'FOUNDRY_API_SCOPE'
              value: passthroughFoundryApiScope
            }
            {
              name: 'APIM_RESPONSES_URL'
              value: passthroughApimResponsesUrl
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

output managedAppName string = managedApp.name
output managedAppUrl string = 'https://${managedApp.properties.configuration.ingress.fqdn}'
output passthroughAppName string = passthroughApp.name
output passthroughAppUrl string = 'https://${passthroughApp.properties.configuration.ingress.fqdn}'

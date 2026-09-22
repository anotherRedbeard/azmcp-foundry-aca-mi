/*
  This template creates an Entra (Azure AD) application with the necessary components
  for secure authentication and authorization in Azure.

  What gets created:

  Entra Application Registration
     This is like a "blueprint" that defines what the Entra App can do. It includes
     app roles (think of these as custom permissions), identifier URIs for OAuth validation,
     and basic app configuration.

  Service Principal
     This is the actual "identity" that represents the Entra App within the Azure
     tenant. This is what you'll assign Azure permissions to, not the app registration itself.

  The Entra App registration defines what the app could do, while the Service Principal
  defines what it can actually do in your specific environment.
*/

extension microsoftGraphV1

@description('Display name for the Entra Application')
param entraAppDisplayName string

@description('Unique name for the Entra Application')
param entraAppUniqueName string

@description('Object ID of the user-assigned managed identity used as the server application credential')
param managedIdentityPrincipalId string

@description('Federated identity credential audience for the target Azure cloud')
param tokenExchangeAudience string

var entraAppScopeValue = 'Mcp.Tools.ReadWrite'
var entraAppScopeId = guid(subscription().id, entraAppScopeValue)
var entraAppScopeDisplayName = 'Azure MCP Tools ReadWrite'
var entraAppScopeDescription = 'Delegated permission for Azure MCP tool calls'

// VS Code client app ID for pre-authorization
var vsCodeClientAppId = 'aebc6443-996d-45c2-90f0-388ff96faa56'
var armMcpApplicationId = '22bfbae3-f4e7-485f-be43-8cee15065084'
var armMcpAccessScopeId = '601b3b64-a3c4-4faa-ab9c-8f97ba332aa3'

resource entraApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: entraAppUniqueName
  displayName: entraAppDisplayName
  requiredResourceAccess: [
    {
      // Azure Resource Manager user_impersonation
      resourceAppId: '797f4846-ba00-4fd7-ba43-dac1f8f63013'
      resourceAccess: [
        {
          id: '41094075-9dad-400e-a0bd-54e686782033'
          type: 'Scope'
        }
      ]
    }
    {
      // Azure Storage user_impersonation
      resourceAppId: 'e406a681-f3d4-42a8-90b6-c2b029497af1'
      resourceAccess: [
        {
          id: '03e0da56-190b-40ad-a80c-ea378c433f7f'
          type: 'Scope'
        }
      ]
    }
    {
      // Azure Resource Manager MCP MCP.Access
      resourceAppId: armMcpApplicationId
      resourceAccess: [
        {
          id: armMcpAccessScopeId
          type: 'Scope'
        }
      ]
    }
  ]
  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        id: entraAppScopeId
        value: entraAppScopeValue
        type: 'User'
        adminConsentDisplayName: entraAppScopeDisplayName
        adminConsentDescription: entraAppScopeDescription
        userConsentDisplayName: entraAppScopeDisplayName
        userConsentDescription: entraAppScopeDescription
        isEnabled: true
      }
    ]
  }
}

resource entraAppUpdate 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: entraAppUniqueName
  displayName: entraAppDisplayName
  appRoles: entraApp.appRoles
  identifierUris: ['api://${entraApp.appId}']
  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: entraApp.api.oauth2PermissionScopes
    preAuthorizedApplications: [
      {
        appId: vsCodeClientAppId
        delegatedPermissionIds: [entraAppScopeId]
      }
    ]
  }
}

resource entraServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: entraApp.appId
}

resource armMcpServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: armMcpApplicationId
}

resource federatedIdentityCredential 'Microsoft.Graph/applications/federatedIdentityCredentials@v1.0' = {
  name: '${entraApp.uniqueName}/AzureMcpServerCredential'
  audiences: [
    tokenExchangeAudience
  ]
  description: 'Managed identity credential used by Azure MCP Server for OBO token exchange'
  issuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
  subject: managedIdentityPrincipalId
}

output entraAppClientId string = entraApp.appId
output entraAppObjectId string = entraApp.id
output entraAppIdentifierUri string = 'api://${entraApp.appId}'
output entraAppScopeValue string = entraAppScopeValue
output entraAppScopeId string = entraApp.api.oauth2PermissionScopes[0].id
output entraAppServicePrincipalObjectId string = entraServicePrincipal.id

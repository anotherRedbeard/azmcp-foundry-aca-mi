targetScope = 'subscription'

@description('Azure Container App managed identity principal/object ID')
param acaPrincipalId string

@description('Azure RBAC role definition ID to grant at subscription scope')
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, acaPrincipalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleDefinitionId
    )
    principalId: acaPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id

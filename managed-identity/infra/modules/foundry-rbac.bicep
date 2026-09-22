@description('Foundry account name')
param accountName string

@description('Foundry project name')
param projectName string

@description('Principal that will invoke the Foundry project')
param principalId string

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: projectName
}

var foundryUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '53ca6127-db72-4b80-b1b0-d745d6d5456d'
)

resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, principalId, foundryUserRoleDefinitionId)
  scope: project
  properties: {
    roleDefinitionId: foundryUserRoleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = foundryUser.id

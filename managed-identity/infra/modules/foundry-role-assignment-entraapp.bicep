extension microsoftGraphV1

@description('Microsoft Foundry project managed identity principal ID')
param foundryProjectPrincipalId string

@description('Entra App Service Principal Object ID (resourceId in Graph API)')
param entraAppServicePrincipalObjectId string

@description('Entra App Role ID to assign')
param entraAppRoleId string

resource appRoleAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: foundryProjectPrincipalId
  resourceId: entraAppServicePrincipalObjectId
  appRoleId: entraAppRoleId
}

output roleAssignmentId string = appRoleAssignment.id
output foundryProjectMIPrincipalId string = foundryProjectPrincipalId

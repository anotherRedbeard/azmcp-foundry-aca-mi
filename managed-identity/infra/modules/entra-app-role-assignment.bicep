extension microsoftGraphV1

@description('Object ID of the managed identity service principal receiving the application role')
param principalId string

@description('Object ID of the resource application service principal')
param resourceServicePrincipalId string

@description('Application role ID to assign')
param appRoleId string

resource appRoleAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  principalId: principalId
  resourceId: resourceServicePrincipalId
  appRoleId: appRoleId
}

output roleAssignmentId string = appRoleAssignment.id

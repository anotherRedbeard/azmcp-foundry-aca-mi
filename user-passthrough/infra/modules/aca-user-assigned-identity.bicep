@description('Location for the user-assigned managed identity')
param location string = resourceGroup().location

@description('Name of the user-assigned managed identity')
param name string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
}

output clientId string = identity.properties.clientId
output principalId string = identity.properties.principalId
output resourceId string = identity.id

@description('Required. Name of the user-assigned managed identity.')
param name string

@description('Required. Location for the resource.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

// ============ //
// Resources    //
// ============ //

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the user-assigned managed identity.')
output name string = userAssignedIdentity.name

@description('The resource ID of the user-assigned managed identity.')
output resourceId string = userAssignedIdentity.id

@description('The principal ID of the user-assigned managed identity.')
output principalId string = userAssignedIdentity.properties.principalId

@description('The client ID of the user-assigned managed identity.')
output clientId string = userAssignedIdentity.properties.clientId

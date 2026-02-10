targetScope = 'managementGroup'

// ============ //
// Parameters   //
// ============ //

@description('Required. The principal ID of the user-assigned managed identity (for Resource Graph queries).')
param userAssignedIdentityPrincipalId string

// ============ //
// Resources    //
// ============ //

// Reader role assignment at management group level for cross-subscription queries (user-assigned identity)
module mgRbacUserAssigned 'modules/rbac-management-group.bicep' = {
  name: 'deploy-mg-rbac-uami'
  params: {
    principalId: userAssignedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The Reader role assignment ID at management group level for user-assigned identity.')
output readerRoleAssignmentId string = mgRbacUserAssigned.outputs.readerRoleAssignmentId

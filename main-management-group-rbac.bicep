targetScope = 'managementGroup'

// ============ //
// Parameters   //
// ============ //

@description('Required. The principal ID of the Logic App managed identity.')
param logicAppPrincipalId string

// ============ //
// Resources    //
// ============ //

// Reader role assignment at management group level for cross-subscription queries
module mgRbac 'modules/rbac-management-group.bicep' = {
  name: 'deploy-mg-rbac'
  params: {
    principalId: logicAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The Reader role assignment ID at management group level.')
output readerRoleAssignmentId string = mgRbac.outputs.readerRoleAssignmentId

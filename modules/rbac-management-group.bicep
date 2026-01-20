targetScope = 'managementGroup'

@description('Required. The principal ID to assign the role to.')
param principalId string

@description('Required. The principal type of the assigned principal ID.')
@allowed([
  'Device'
  'ForeignGroup'
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string = 'ServicePrincipal'

// ============ //
// Variables    //
// ============ //

// Reader role definition ID: acdd72a7-3385-48ef-bd42-f606fba81ae7
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// ============ //
// Resources    //
// ============ //

// Reader role assignment at management group level for cross-subscription Azure Resource Graph queries
resource readerRoleAssignmentManagementGroup 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managementGroup().id, principalId, readerRoleId)
  properties: {
    roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: principalId
    principalType: principalType
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The resource ID of the Reader role assignment at management group level.')
output readerRoleAssignmentId string = readerRoleAssignmentManagementGroup.id

@description('The management group name where the role was assigned.')
output managementGroupName string = managementGroup().name

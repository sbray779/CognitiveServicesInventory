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

@description('Required. The resource ID of the Data Collection Rule for Monitoring Metrics Publisher role.')
param dataCollectionRuleId string

@description('Optional. The management group ID for Resource Graph Reader role. If not provided, role will be assigned at subscription level.')
param managementGroupId string = ''

// ============ //
// Variables    //
// ============ //

// Built-in role definition IDs
// Monitoring Metrics Publisher: 3913510d-42f4-4e42-8a64-420c390055eb
// Reader: acdd72a7-3385-48ef-bd42-f606fba81ae7

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// ============ //
// Resources    //
// ============ //

// Reference the existing DCR
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: last(split(dataCollectionRuleId, '/'))
}

// Monitoring Metrics Publisher role assignment on the DCR
// This allows the Logic App to send data to the DCR
resource monitoringMetricsPublisherRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRuleId, principalId, monitoringMetricsPublisherRoleId)
  scope: dataCollectionRule
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: principalId
    principalType: principalType
  }
}

// Reader role assignment at subscription level for Azure Resource Graph queries
// This allows the Logic App to query resources across the subscription
resource readerRoleAssignmentSubscription 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(managementGroupId)) {
  name: guid(subscription().id, principalId, readerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: principalId
    principalType: principalType
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The resource ID of the Monitoring Metrics Publisher role assignment.')
output monitoringMetricsPublisherRoleAssignmentId string = monitoringMetricsPublisherRoleAssignment.id

@description('The resource ID of the Reader role assignment at subscription level.')
output readerRoleAssignmentId string = empty(managementGroupId) ? readerRoleAssignmentSubscription.id : ''

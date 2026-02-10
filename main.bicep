targetScope = 'subscription'

// ============ //
// Parameters   //
// ============ //

@description('Required. Name of the existing Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('Required. Resource group name where the Log Analytics workspace exists.')
param logAnalyticsWorkspaceResourceGroupName string

@description('Required. The resource group name for deploying new resources.')
param resourceGroupName string

@description('Required. Location for all resources.')
param location string

@description('Optional. Custom table name (without _CL suffix). Default is CognitiveServicesInventory.')
param customTableName string = 'CognitiveServicesInventory'

@description('Optional. Prefix for all resource names.')
param resourcePrefix string = 'cogai'

@description('Optional. Tags to apply to all resources.')
param tags object = {}

@description('Optional. Management group ID for cross-subscription Resource Graph queries. Leave empty for subscription-level scope.')
param managementGroupId string = ''

// ============ //
// Variables    //
// ============ //

var uniqueSuffix = uniqueString(subscription().id, resourceGroupName)
var dceNameVar = '${resourcePrefix}-dce-${uniqueSuffix}'
var dcrNameVar = '${resourcePrefix}-dcr-${uniqueSuffix}'
var storageNameVar = '${resourcePrefix}st${uniqueSuffix}'
var logicAppNameVar = '${resourcePrefix}-logicapp-${uniqueSuffix}'
var appServicePlanNameVar = '${resourcePrefix}-asp-${uniqueSuffix}'
var userAssignedIdentityNameVar = '${resourcePrefix}-uami-${uniqueSuffix}'

// Get the Log Analytics workspace resource ID (construct manually since we're at subscription scope)
var logAnalyticsWorkspaceResourceId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${logAnalyticsWorkspaceResourceGroupName}/providers/Microsoft.OperationalInsights/workspaces/${logAnalyticsWorkspaceName}'

// ============ //
// Resources    //
// ============ //

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Reference existing Log Analytics workspace resource group for custom table deployment
resource laWorkspaceRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: logAnalyticsWorkspaceResourceGroupName
}

// Custom Table in Log Analytics
module customTable 'modules/custom-table.bicep' = {
  name: 'deploy-custom-table'
  scope: laWorkspaceRg
  params: {
    name: customTableName
    workspaceName: logAnalyticsWorkspaceName
  }
}

// Data Collection Endpoint
module dce 'modules/data-collection-endpoint.bicep' = {
  name: 'deploy-dce'
  scope: rg
  params: {
    name: dceNameVar
    location: location
    tags: tags
    publicNetworkAccess: 'Enabled'
  }
}

// Data Collection Rule
module dcr 'modules/data-collection-rule.bicep' = {
  name: 'deploy-dcr'
  scope: rg
  dependsOn: [
    customTable
  ]
  params: {
    name: dcrNameVar
    location: location
    tags: tags
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    dataCollectionEndpointResourceId: dce.outputs.resourceId
    customTableName: customTableName
  }
}

// Storage Account for Logic App
module storageAccount 'modules/storage-account.bicep' = {
  name: 'deploy-storage'
  scope: rg
  params: {
    name: storageNameVar
    location: location
    tags: tags
  }
}

// App Service Plan for Logic App (Standard)
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'deploy-asp'
  scope: rg
  params: {
    name: appServicePlanNameVar
    location: location
    tags: tags
  }
}

// User-Assigned Managed Identity for Azure Resource Graph queries
module userAssignedIdentity 'modules/user-assigned-identity.bicep' = {
  name: 'deploy-uami'
  scope: rg
  params: {
    name: userAssignedIdentityNameVar
    location: location
    tags: tags
  }
}

// Logic App (Standard)
module logicApp 'modules/logic-app.bicep' = {
  name: 'deploy-logicapp'
  scope: rg
  params: {
    name: logicAppNameVar
    location: location
    tags: tags
    storageAccountName: storageAccount.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    enableManagedIdentity: true
    userAssignedIdentityId: userAssignedIdentity.outputs.resourceId
    userAssignedIdentityResourceId: userAssignedIdentity.outputs.resourceId
    dceLogsIngestionEndpoint: dce.outputs.logsIngestionEndpoint
    dcrImmutableId: dcr.outputs.immutableId
    dcrStreamName: dcr.outputs.streamName
    managementGroupId: managementGroupId
  }
}

// RBAC Assignments for the Logic App (system-assigned identity for DCR access)
module rbacAssignments 'modules/rbac-assignments.bicep' = {
  name: 'deploy-rbac'
  scope: rg
  params: {
    principalId: logicApp.outputs.principalId
    principalType: 'ServicePrincipal'
    dataCollectionRuleId: dcr.outputs.resourceId
    managementGroupId: managementGroupId
  }
}

// RBAC Assignments for the User-Assigned Managed Identity (Reader for Resource Graph queries)
module rbacUserAssignedIdentity 'modules/rbac-assignments.bicep' = {
  name: 'deploy-rbac-uami'
  scope: rg
  params: {
    principalId: userAssignedIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    dataCollectionRuleId: dcr.outputs.resourceId
    managementGroupId: managementGroupId
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The resource group name.')
output resourceGroupName string = rg.name

@description('The Data Collection Endpoint name.')
output dceName string = dce.outputs.name

@description('The Data Collection Endpoint logs ingestion endpoint.')
output dceLogsIngestionEndpoint string = dce.outputs.logsIngestionEndpoint

@description('The Data Collection Rule name.')
output dcrName string = dcr.outputs.name

@description('The Data Collection Rule immutable ID.')
output dcrImmutableId string = dcr.outputs.immutableId

@description('The Data Collection Rule stream name.')
output dcrStreamName string = dcr.outputs.streamName

@description('The Storage Account name.')
output storageAccountName string = storageAccount.outputs.name

@description('The Logic App name.')
output logicAppName string = logicApp.outputs.name

@description('The Logic App default hostname.')
output logicAppHostName string = logicApp.outputs.defaultHostName

@description('The Logic App managed identity principal ID.')
output logicAppPrincipalId string = logicApp.outputs.principalId

@description('The custom table name in Log Analytics.')
output customTableName string = customTable.outputs.name

@description('The user-assigned managed identity name.')
output userAssignedIdentityName string = userAssignedIdentity.outputs.name

@description('The user-assigned managed identity resource ID.')
output userAssignedIdentityResourceId string = userAssignedIdentity.outputs.resourceId

@description('The user-assigned managed identity client ID.')
output userAssignedIdentityClientId string = userAssignedIdentity.outputs.clientId

@description('The user-assigned managed identity principal ID.')
output userAssignedIdentityPrincipalId string = userAssignedIdentity.outputs.principalId

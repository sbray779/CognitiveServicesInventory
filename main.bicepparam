using 'main.bicep'

// Required parameters
param logAnalyticsWorkspaceName = 'ChargeBackWorkspace'
param logAnalyticsWorkspaceResourceGroupName = 'AIHubChargeBack'
param resourceGroupName = 'TestChargeBack'
param location = 'eastus2'

// Optional parameters
param customTableName = 'CognitiveServicesInventory'
param resourcePrefix = 'cogai'
param tags = {
  Environment: 'Production'
  Project: 'CognitiveServicesInventory'
  ManagedBy: 'Bicep'
}

// Leave empty for subscription-level scope, or provide management group ID for cross-subscription queries
param managementGroupId = ''

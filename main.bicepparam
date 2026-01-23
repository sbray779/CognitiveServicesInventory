using 'main.bicep'

// Required parameters
param logAnalyticsWorkspaceName = '<Your-Log-Analytics-Workspace-Name>'
param logAnalyticsWorkspaceResourceGroupName = '<Your-Log-Analytics-Workspace-Resource-Group-Name>'
param resourceGroupName = '<Cognitive-Services-Resource-Group-Name>'
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

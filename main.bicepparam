using 'main.bicep'

// Required parameters
param logAnalyticsWorkspaceName = '<your-log-analytics-workspace-name>'
param logAnalyticsWorkspaceResourceGroupName = '<your-log-analytics-workspace-resource-group-name>'
param resourceGroupName = '<your-resource-group-name>'
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

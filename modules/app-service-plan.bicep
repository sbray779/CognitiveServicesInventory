@description('Required. Name of the App Service Plan.')
param name string

@description('Required. Location for all resources.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

@description('Optional. SKU name for the App Service Plan. Default is WS1 (Workflow Standard).')
param skuName string = 'WS1'

@description('Optional. SKU tier for the App Service Plan. Default is WorkflowStandard.')
param skuTier string = 'WorkflowStandard'

@description('Optional. Maximum number of elastic workers.')
param maximumElasticWorkerCount int = 20

// ============ //
// Resources    //
// ============ //

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: maximumElasticWorkerCount
    zoneRedundant: false
    reserved: false
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the App Service Plan.')
output name string = appServicePlan.name

@description('The resource ID of the App Service Plan.')
output resourceId string = appServicePlan.id

@description('The resource group the App Service Plan was deployed into.')
output resourceGroupName string = resourceGroup().name

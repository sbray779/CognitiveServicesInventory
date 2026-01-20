@description('Required. Name of the Data Collection Endpoint.')
param name string

@description('Required. Location for all resources.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

@description('Optional. The kind of the resource. Default is Linux.')
@allowed([
  'Linux'
  'Windows'
])
param kind string = 'Linux'

@description('Optional. The configuration to set whether network access from public internet to the endpoints are allowed.')
@allowed([
  'Enabled'
  'Disabled'
  'SecuredByPerimeter'
])
param publicNetworkAccess string = 'Enabled'

@description('Optional. Description of the Data Collection Endpoint.')
param resourceDescription string = ''

// ============ //
// Resources    //
// ============ //

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: name
  location: location
  tags: tags
  kind: kind
  properties: {
    description: resourceDescription
    networkAcls: {
      publicNetworkAccess: publicNetworkAccess
    }
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the Data Collection Endpoint.')
output name string = dataCollectionEndpoint.name

@description('The resource ID of the Data Collection Endpoint.')
output resourceId string = dataCollectionEndpoint.id

@description('The resource group the Data Collection Endpoint was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The logs ingestion endpoint of the Data Collection Endpoint.')
output logsIngestionEndpoint string = dataCollectionEndpoint.properties.logsIngestion.endpoint

@description('The configuration access endpoint of the Data Collection Endpoint.')
output configurationAccessEndpoint string = dataCollectionEndpoint.properties.configurationAccess.endpoint

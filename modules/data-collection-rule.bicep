@description('Required. Name of the Data Collection Rule.')
param name string

@description('Required. Location for all resources.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

@description('Required. The resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceResourceId string

@description('Required. The resource ID of the Data Collection Endpoint.')
param dataCollectionEndpointResourceId string

@description('Required. The name of the custom table in Log Analytics (without the _CL suffix).')
param customTableName string

@description('Optional. Description of the Data Collection Rule.')
param ruleDescription string = 'DCR for ingesting Cognitive Services deployment inventory to custom Log Analytics table'

// ============ //
// Variables    //
// ============ //

var streamName = 'Custom-${customTableName}_CL'
var tableName = '${customTableName}_CL'

// ============ //
// Resources    //
// ============ //

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: name
  location: location
  tags: tags
  kind: 'Direct'
  properties: {
    description: ruleDescription
    dataCollectionEndpointId: dataCollectionEndpointResourceId
    streamDeclarations: {
      '${streamName}': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'DeploymentId'
            type: 'string'
          }
          {
            name: 'DeploymentName'
            type: 'string'
          }
          {
            name: 'ModelName'
            type: 'string'
          }
          {
            name: 'ModelVersion'
            type: 'string'
          }
          {
            name: 'ModelFormat'
            type: 'string'
          }
          {
            name: 'SkuName'
            type: 'string'
          }
          {
            name: 'SkuCapacity'
            type: 'int'
          }
          {
            name: 'AccountName'
            type: 'string'
          }
          {
            name: 'AccountId'
            type: 'string'
          }
          {
            name: 'AccountKind'
            type: 'string'
          }
          {
            name: 'AccountEndpoint'
            type: 'string'
          }
          {
            name: 'SubscriptionId'
            type: 'string'
          }
          {
            name: 'SubscriptionName'
            type: 'string'
          }
          {
            name: 'ResourceGroup'
            type: 'string'
          }
          {
            name: 'Location'
            type: 'string'
          }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspaceResourceId
          name: 'logAnalyticsWorkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          streamName
        ]
        destinations: [
          'logAnalyticsWorkspace'
        ]
        transformKql: 'source | project TimeGenerated, DeploymentId, DeploymentName, ModelName, ModelVersion, ModelFormat, SkuName, SkuCapacity, AccountName, AccountId, AccountKind, AccountEndpoint, SubscriptionId, SubscriptionName, ResourceGroup, Location'
        outputStream: streamName
      }
    ]
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the Data Collection Rule.')
output name string = dataCollectionRule.name

@description('The resource ID of the Data Collection Rule.')
output resourceId string = dataCollectionRule.id

@description('The resource group the Data Collection Rule was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The immutable ID of the Data Collection Rule.')
output immutableId string = dataCollectionRule.properties.immutableId

@description('The stream name for the custom table.')
output streamName string = streamName

@description('The custom table name.')
output tableName string = tableName

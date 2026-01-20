@description('Required. Name of the custom table (without the _CL suffix).')
param name string

@description('Required. Name of the existing Log Analytics workspace.')
param workspaceName string

@description('Optional. Retention time in days. Default is 30 days.')
@minValue(4)
@maxValue(730)
param retentionInDays int = 30

@description('Optional. Total retention time in days including archive. Default is 365 days.')
@minValue(4)
@maxValue(2556)
param totalRetentionInDays int = 365

// ============ //
// Variables    //
// ============ //

var tableName = '${name}_CL'

// ============ //
// Resources    //
// ============ //

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: [
        {
          name: 'TimeGenerated'
          type: 'datetime'
          description: 'The time the record was generated'
        }
        {
          name: 'ResourceId'
          type: 'string'
          description: 'Azure Resource ID of the Cognitive Service'
        }
        {
          name: 'ResourceName'
          type: 'string'
          description: 'Name of the Cognitive Service resource'
        }
        {
          name: 'ResourceType'
          type: 'string'
          description: 'Type of the Cognitive Service resource'
        }
        {
          name: 'Kind'
          type: 'string'
          description: 'Kind/SKU tier of the Cognitive Service'
        }
        {
          name: 'Location'
          type: 'string'
          description: 'Azure region where the resource is deployed'
        }
        {
          name: 'SubscriptionId'
          type: 'string'
          description: 'Subscription ID containing the resource'
        }
        {
          name: 'SubscriptionName'
          type: 'string'
          description: 'Subscription name containing the resource'
        }
        {
          name: 'ResourceGroup'
          type: 'string'
          description: 'Resource group containing the resource'
        }
        {
          name: 'Sku'
          type: 'string'
          description: 'SKU name of the Cognitive Service'
        }
        {
          name: 'ProvisioningState'
          type: 'string'
          description: 'Provisioning state of the resource'
        }
        {
          name: 'PublicNetworkAccess'
          type: 'string'
          description: 'Public network access setting'
        }
        {
          name: 'Endpoint'
          type: 'string'
          description: 'The endpoint URL of the Cognitive Service'
        }
      ]
    }
    retentionInDays: retentionInDays
    totalRetentionInDays: totalRetentionInDays
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the custom table.')
output name string = customTable.name

@description('The resource ID of the custom table.')
output resourceId string = customTable.id

@description('The workspace name.')
output workspaceName string = workspace.name

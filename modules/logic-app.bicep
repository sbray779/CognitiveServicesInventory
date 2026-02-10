@description('Required. Name of the Logic App.')
param name string

@description('Required. Location for all resources.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

@description('Required. Name of the storage account for Logic App.')
param storageAccountName string

@description('Required. Resource ID of the App Service Plan.')
param appServicePlanId string

@description('Optional. Enable system-assigned managed identity.')
param enableManagedIdentity bool = true

@description('Optional. Resource ID of the user-assigned managed identity for Azure Resource Graph queries.')
param userAssignedIdentityId string = ''

@description('Optional. Resource ID of the user-assigned managed identity for workflow authentication (same as userAssignedIdentityId).')
param userAssignedIdentityResourceId string = ''

@description('Optional. Data Collection Endpoint logs ingestion endpoint URL.')
param dceLogsIngestionEndpoint string = ''

@description('Optional. Data Collection Rule immutable ID.')
param dcrImmutableId string = ''

@description('Optional. Data Collection Rule stream name.')
param dcrStreamName string = ''

@description('Optional. Management group ID for scoping Resource Graph queries.')
param managementGroupId string = ''

// ============ //
// Resources    //
// ============ //

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

// Determine identity type based on what's enabled
var hasUserAssignedIdentity = !empty(userAssignedIdentityId)
var identityType = enableManagedIdentity && hasUserAssignedIdentity ? 'SystemAssigned, UserAssigned' : (enableManagedIdentity ? 'SystemAssigned' : (hasUserAssignedIdentity ? 'UserAssigned' : 'None'))

resource logicApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: identityType
    userAssignedIdentities: hasUserAssignedIdentity ? {
      '${userAssignedIdentityId}': {}
    } : null
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(name)
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        // User-assigned managed identity resource ID for workflow authentication
        {
          name: 'USER_ASSIGNED_IDENTITY_RESOURCE_ID'
          value: userAssignedIdentityResourceId
        }
        {
          name: 'DCE_LOGS_INGESTION_ENDPOINT'
          value: dceLogsIngestionEndpoint
        }
        {
          name: 'DCR_IMMUTABLE_ID'
          value: dcrImmutableId
        }
        {
          name: 'DCR_STREAM_NAME'
          value: dcrStreamName
        }
        {
          name: 'MANAGEMENT_GROUP_ID'
          value: managementGroupId
        }
      ]
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the Logic App.')
output name string = logicApp.name

@description('The resource ID of the Logic App.')
output resourceId string = logicApp.id

@description('The resource group the Logic App was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The principal ID of the Logic App managed identity.')
output principalId string = enableManagedIdentity ? logicApp.identity!.principalId : ''

@description('The default hostname of the Logic App.')
output defaultHostName string = logicApp.properties.defaultHostName

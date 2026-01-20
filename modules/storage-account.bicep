@description('Required. Name of the Storage Account.')
param name string

@description('Required. Location for all resources.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

@description('Optional. Storage Account SKU. Default is Standard_LRS.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Optional. Storage Account Kind. Default is StorageV2.')
@allowed([
  'Storage'
  'StorageV2'
  'BlobStorage'
  'FileStorage'
  'BlockBlobStorage'
])
param kind string = 'StorageV2'

@description('Optional. Allow or disallow public access to all blobs or containers in the storage account.')
param allowBlobPublicAccess bool = false

@description('Optional. Allows https traffic only to storage service.')
param supportsHttpsTrafficOnly bool = true

@description('Optional. Set the minimum TLS version.')
@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
param minimumTlsVersion string = 'TLS1_2'

// ============ //
// Resources    //
// ============ //

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: kind
  properties: {
    allowBlobPublicAccess: allowBlobPublicAccess
    supportsHttpsTrafficOnly: supportsHttpsTrafficOnly
    minimumTlsVersion: minimumTlsVersion
    accessTier: 'Hot'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// ============ //
// Outputs      //
// ============ //

@description('The name of the Storage Account.')
output name string = storageAccount.name

@description('The resource ID of the Storage Account.')
output resourceId string = storageAccount.id

@description('The resource group the Storage Account was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The primary endpoints of the Storage Account.')
output primaryEndpoints object = storageAccount.properties.primaryEndpoints

@description('The primary blob endpoint of the Storage Account.')
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

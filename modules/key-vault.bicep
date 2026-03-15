// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('Service Bus namespace name used to resolve RootManageSharedAccessKey connection string')
param serviceBusNamespaceName string

@description('Azure AD tenant ID')
param tenantId string

@description('Set to recover to restore a soft-deleted vault with the same name')
param createMode string = 'default'

// Key Vault names must be 3-24 chars, alphanumeric + hyphens. baseName can be ~22 chars.
var vaultName = take('${baseName}-kv', 24)

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource serviceBusIntakeSenderRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' existing = {
  parent: serviceBusNamespace
  name: 'intake-sender-key'
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    createMode: createMode
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
  }
}

resource sbConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'ServiceBusConnectionString'
  properties: {
    value: serviceBusIntakeSenderRule.listKeys().primaryConnectionString
    contentType: 'text/plain'
  }
}

@description('Key Vault URI')
output vaultUri string = vault.properties.vaultUri

@description('Key Vault name')
output vaultName string = vault.name

@description('Key Vault resource ID')
output vaultId string = vault.id

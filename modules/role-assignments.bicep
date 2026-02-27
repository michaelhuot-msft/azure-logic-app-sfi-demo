// Licensed under the Apache License, Version 2.0

@description('Service Bus namespace name')
param serviceBusNamespaceName string

@description('Key Vault name')
param keyVaultName string

@description('Intake Logic App managed identity principal ID')
param intakePrincipalId string

@description('Router Logic App managed identity principal ID')
param routerPrincipalId string

// Role definition IDs
var sbDataSenderRole = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var sbDataReceiverRole = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var kvSecretsUserRole = '4633458b-17de-408a-b874-0445c86b69e6'

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Intake Logic App → Service Bus Data Sender
resource intakeSbSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, intakePrincipalId, sbDataSenderRole)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataSenderRole)
    principalId: intakePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Router Logic App → Service Bus Data Sender (sends to urgent/standard queues)
resource routerSbSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, routerPrincipalId, sbDataSenderRole)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataSenderRole)
    principalId: routerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Router Logic App → Service Bus Data Receiver (reads from incoming queue)
resource routerSbReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, routerPrincipalId, sbDataReceiverRole)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataReceiverRole)
    principalId: routerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Intake Logic App → Key Vault Secrets User
resource intakeKvReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, intakePrincipalId, kvSecretsUserRole)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRole)
    principalId: intakePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Router Logic App → Key Vault Secrets User
resource routerKvReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, routerPrincipalId, kvSecretsUserRole)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRole)
    principalId: routerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

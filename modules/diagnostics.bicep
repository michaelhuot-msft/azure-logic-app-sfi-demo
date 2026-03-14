// Licensed under the Apache License, Version 2.0

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Logic App Standard name')
param intakeLogicAppName string

@description('Service Bus namespace name')
param serviceBusNamespaceName string

@description('Key Vault name')
param keyVaultName string

@description('APIM name')
param apimName string

resource logicAppStandard 'Microsoft.Web/sites@2024-04-01' existing = {
  name: intakeLogicAppName
}

resource logicAppDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: logicAppStandard
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
      }
      {
        category: 'FunctionAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource sbDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: serviceBusNamespace
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'OperationalLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource kvDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Note: APIM Consumption tier has limited diagnostic log categories
resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

resource apimDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: apimService
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

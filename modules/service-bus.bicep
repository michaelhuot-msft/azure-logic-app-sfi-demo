// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

var namespaceName = '${baseName}-sbns'

resource namespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: 1
  }
  properties: {
    // Consumption Logic Apps use the shared API connector infrastructure which
    // connects over the public internet — public access must be enabled.
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: '1.2'
    premiumMessagingPartitions: 1
  }
}

// Network rule set: deny all public access, trust Azure services only
resource networkRuleSet 'Microsoft.ServiceBus/namespaces/networkRuleSets@2022-10-01-preview' = {
  parent: namespace
  name: 'default'
  properties: {
    publicNetworkAccess: 'Enabled'
    defaultAction: 'Allow'
    trustedServiceAccessEnabled: true
    ipRules: []
    virtualNetworkRules: []
  }
}

resource incomingQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: namespace
  name: 'incoming-referrals'
  properties: {
    maxDeliveryCount: 10
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
  }
}

resource urgentQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: namespace
  name: 'urgent-referrals'
  properties: {
    maxDeliveryCount: 10
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
  }
}

resource standardQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: namespace
  name: 'standard-referrals'
  properties: {
    maxDeliveryCount: 10
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
  }
}

// Per-application authorization rules (least-privilege, replaces RootManageSharedAccessKey usage)
resource intakeSenderRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: namespace
  name: 'intake-sender-key'
  properties: {
    rights: [
      'Send'
    ]
  }
}

resource routerReceiverRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: namespace
  name: 'router-receiver-key'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

@description('Service Bus namespace name')
output namespaceName string = namespace.name

@description('Service Bus namespace resource ID')
output namespaceId string = namespace.id

@description('Intake sender authorization rule name')
output intakeSenderRuleName string = intakeSenderRule.name

@description('Router receiver authorization rule name')
output routerReceiverRuleName string = routerReceiverRule.name

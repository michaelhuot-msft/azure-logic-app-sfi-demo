// Copyright 2025 HACS Group
// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('VNet resource ID for Bastion association')
param vnetId string

@description('Subnet resource ID for the jumpbox VM NIC')
param jumpboxSubnetId string

@description('Admin username for the jumpbox VM')
param adminUsername string = 'azureadmin'

@secure()
@description('Admin password for the jumpbox VM')
param adminPassword string

@description('VM size for the jumpbox')
param vmSize string = 'Standard_D2als_v7'

var bastionName = '${baseName}-bastion'
var vmName = '${baseName}-jbox'
var nicName = '${vmName}-nic'

// ──────────────────────────────────────────────
// Azure Bastion — Developer SKU (no public IP, no dedicated subnet)
// ──────────────────────────────────────────────
resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

// ──────────────────────────────────────────────
// Jumpbox VM — Windows Server 2022, no public IP (SFI compliant)
// ──────────────────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: jumpboxSubnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'jumpbox'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// Auto-shutdown at 7 PM to save costs in dev/demo environments
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '1900'
    }
    timeZoneId: 'Eastern Standard Time'
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

@description('Bastion host name')
output bastionName string = bastion.name

@description('Jumpbox VM name')
output vmName string = vm.name

@description('Jumpbox private IP address')
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress

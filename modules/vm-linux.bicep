param name string
param location string
param subnetId string
param adminUsername string = 'azureuser'
@secure()
param adminSshPublicKey string
param vmSize string = 'Standard_B1s'
param withPublicIp bool = true
param enableIpForwarding bool = false

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (withPublicIp) {
  name: '${name}-pip'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${name}-nic'
  location: location
  properties: {
    enableIPForwarding: enableIpForwarding
    ipConfigurations: [
      {
        name: 'ipc'
        properties: union({
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
        }, withPublicIp ? { publicIPAddress: { id: pip.id } } : {})
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
}

output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output publicIp string = withPublicIp ? pip.properties.ipAddress : ''

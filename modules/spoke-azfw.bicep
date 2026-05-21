param name string
param location string
param azfwSubnetId string
param firewallPolicyId string

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${name}-pip'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource azfw 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'azfw-ipc'
        properties: {
          subnet: { id: azfwSubnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
    firewallPolicy: {
      id: firewallPolicyId
    }
  }
}

output id string = azfw.id
output privateIp string = azfw.properties.ipConfigurations[0].properties.privateIPAddress
output publicIp string = pip.properties.ipAddress

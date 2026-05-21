param name string
param location string
param hubId string
param firewallPolicyId string

resource azfw 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'AZFW_Hub'
      tier: 'Standard'
    }
    virtualHub: {
      id: hubId
    }
    hubIPAddresses: {
      publicIPs: {
        count: 1
      }
    }
    firewallPolicy: {
      id: firewallPolicyId
    }
  }
}

output id string = azfw.id

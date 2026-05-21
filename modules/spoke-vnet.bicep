param name string
param location string
param addressSpace string
param subnets array
param homeIp string = '115.70.58.97'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${name}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh-home'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: homeIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'allow-vnet-icmp'
        properties: {
          priority: 200
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: '10.0.0.0/8'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ addressSpace ]
    }
    subnets: [for s in subnets: {
      name: s.name
      properties: union({
        addressPrefix: s.addressPrefix
      }, s.name == 'AzureFirewallSubnet' ? {} : {
        networkSecurityGroup: { id: nsg.id }
      })
    }]
  }
}

output id string = vnet.id
output name string = vnet.name
output subnetIds object = toObject(vnet.properties.subnets, s => s.name, s => s.id)

param name string
param location string

resource vwan 'Microsoft.Network/virtualWans@2024-05-01' = {
  name: name
  location: location
  properties: {
    type: 'Standard'
    allowBranchToBranchTraffic: true
    disableVpnEncryption: false
  }
}

output id string = vwan.id
output name string = vwan.name

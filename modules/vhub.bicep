param name string
param location string
param addressPrefix string
param vwanId string
param sku string = 'Standard'

resource vhub 'Microsoft.Network/virtualHubs@2024-05-01' = {
  name: name
  location: location
  properties: {
    addressPrefix: addressPrefix
    virtualWan: {
      id: vwanId
    }
    sku: sku
  }
}

output id string = vhub.id
output name string = vhub.name

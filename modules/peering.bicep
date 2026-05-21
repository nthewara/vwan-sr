param localVnetName string
param remoteVnetId string
param peeringName string
param allowGatewayTransit bool = false
param useRemoteGateways bool = false

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${localVnetName}/${peeringName}'
  properties: {
    remoteVirtualNetwork: { id: remoteVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
  }
}

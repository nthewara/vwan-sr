param hubName string
param connectionName string
param remoteVnetId string
param staticRoutes array = []
param propagateStaticRoutes bool = false
param vnetLocalRouteTableNextHopIp string = ''

resource connection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  name: '${hubName}/${connectionName}'
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: false
    routingConfiguration: {
      vnetRoutes: {
        staticRoutes: staticRoutes
        staticRoutesConfig: {
          propagateStaticRoutes: propagateStaticRoutes
          vnetLocalRouteOverrideCriteria: 'Contains'
        }
      }
    }
  }
}

output id string = connection.id

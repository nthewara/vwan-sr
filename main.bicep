targetScope = 'resourceGroup'

@description('Prefix for all resources')
param prefix string = 'vwansr'

@description('Azure region')
param location string = resourceGroup().location

@description('SSH public key for VM access')
@secure()
param adminSshPublicKey string

@description('Home/admin source IP allowed to SSH')
param homeIp string = '115.70.58.97'

@description('Set to true to add static routes (do AFTER initial deploy succeeds)')
param enableStaticRoutes bool = false

// =====================
// Naming
// =====================
var uniq = take(uniqueString(resourceGroup().id), 5)
var p = '${prefix}-${uniq}'

// Address space plan
var hub1Cidr = '10.10.0.0/23'
var hub2Cidr = '10.11.0.0/23'
var spoke1Cidr = '10.20.0.0/16'
var spoke2Cidr = '10.30.0.0/16'
var indirectCidr = '10.40.0.0/16'

// =====================
// vWAN + Hubs
// =====================
module vwan 'modules/vwan.bicep' = {
  name: 'vwan'
  params: {
    name: '${p}-vwan'
    location: location
  }
}

module hub1 'modules/vhub.bicep' = {
  name: 'hub1'
  params: {
    name: '${p}-hub1'
    location: location
    addressPrefix: hub1Cidr
    vwanId: vwan.outputs.id
  }
}

module hub2 'modules/vhub.bicep' = {
  name: 'hub2'
  params: {
    name: '${p}-hub2'
    location: location
    addressPrefix: hub2Cidr
    vwanId: vwan.outputs.id
  }
}

// =====================
// Firewall policy (shared)
// =====================
module fwPolicy 'modules/fw-policy.bicep' = {
  name: 'fw-policy'
  params: {
    name: '${p}-fwpol'
    location: location
  }
}

// Hub-attached AzFW in Hub1
module hub1Fw 'modules/hub-azfw.bicep' = {
  name: 'hub1-azfw'
  params: {
    name: '${p}-hub1-azfw'
    location: location
    hubId: hub1.outputs.id
    firewallPolicyId: fwPolicy.outputs.id
  }
}

// =====================
// Spoke VNets
// =====================
module spoke1 'modules/spoke-vnet.bicep' = {
  name: 'spoke1'
  params: {
    name: '${p}-spoke1'
    location: location
    addressSpace: spoke1Cidr
    homeIp: homeIp
    subnets: [
      { name: 'vms', addressPrefix: '10.20.1.0/24' }
    ]
  }
}

module spoke2 'modules/spoke-vnet.bicep' = {
  name: 'spoke2'
  params: {
    name: '${p}-spoke2'
    location: location
    addressSpace: spoke2Cidr
    homeIp: homeIp
    subnets: [
      { name: 'AzureFirewallSubnet', addressPrefix: '10.30.0.0/26' }
      { name: 'vms', addressPrefix: '10.30.1.0/24' }
    ]
  }
}

module indirect 'modules/spoke-vnet.bicep' = {
  name: 'indirect'
  params: {
    name: '${p}-indirect'
    location: location
    addressSpace: indirectCidr
    homeIp: homeIp
    subnets: [
      { name: 'vms', addressPrefix: '10.40.1.0/24' }
    ]
  }
}

// Spoke-deployed AzFW (in spoke2) — acts as NVA for static-route demo
module spoke2Fw 'modules/spoke-azfw.bicep' = {
  name: 'spoke2-azfw'
  params: {
    name: '${p}-spoke2-azfw'
    location: location
    azfwSubnetId: spoke2.outputs.subnetIds.AzureFirewallSubnet
    firewallPolicyId: fwPolicy.outputs.id
  }
}

// =====================
// Peering: spoke2 <-> indirect
// =====================
module peerS2toIndirect 'modules/peering.bicep' = {
  name: 'peer-s2-indirect'
  params: {
    localVnetName: spoke2.outputs.name
    remoteVnetId: indirect.outputs.id
    peeringName: 'to-indirect'
  }
}

module peerIndirectToS2 'modules/peering.bicep' = {
  name: 'peer-indirect-s2'
  params: {
    localVnetName: indirect.outputs.name
    remoteVnetId: spoke2.outputs.id
    peeringName: 'to-spoke2'
  }
}

// =====================
// Hub VNet connections (Phase A: no static routes)
// Phase B: re-deploy with enableStaticRoutes=true to add static routes
// =====================

// Hub1 -> spoke1
var hub1Spoke1StaticRoutes = enableStaticRoutes ? [
  {
    name: 'to-spoke2-via-azfw'
    addressPrefixes: [ spoke2Cidr ]
    nextHopIpAddress: ''
  }
] : []

module hub1ToSpoke1 'modules/hub-vnet-connection.bicep' = {
  name: 'hub1-to-spoke1'
  params: {
    hubName: hub1.outputs.name
    connectionName: 'to-spoke1'
    remoteVnetId: spoke1.outputs.id
  }
}

// Hub2 -> spoke2  (Phase B: add static route 10.40/16 -> spoke2 AzFW private IP)
var hub2Spoke2StaticRoutes = enableStaticRoutes ? [
  {
    name: 'to-indirect-via-spoke2-azfw'
    addressPrefixes: [ indirectCidr ]
    nextHopIpAddress: spoke2Fw.outputs.privateIp
  }
] : []

module hub2ToSpoke2 'modules/hub-vnet-connection.bicep' = {
  name: 'hub2-to-spoke2'
  params: {
    hubName: hub2.outputs.name
    connectionName: 'to-spoke2'
    remoteVnetId: spoke2.outputs.id
    staticRoutes: hub2Spoke2StaticRoutes
    propagateStaticRoutes: enableStaticRoutes
  }
  dependsOn: [ spoke2Fw ]
}

// =====================
// Hub1 defaultRouteTable static route -> Hub1 AzFW (east-west)
// =====================
resource hub1DefaultRT 'Microsoft.Network/virtualHubs/hubRouteTables@2024-05-01' = if (enableStaticRoutes) {
  name: '${p}-hub1/defaultRouteTable'
  properties: {
    labels: [ 'default' ]
    routes: [
      {
        name: 'all-private-via-azfw'
        destinationType: 'CIDR'
        destinations: [ '10.0.0.0/8' ]
        nextHopType: 'ResourceId'
        nextHop: hub1Fw.outputs.id
      }
    ]
  }
  dependsOn: [ hub1, hub1Fw, hub1ToSpoke1 ]
}

// =====================
// Demo VMs
// =====================
module vm1 'modules/vm-linux.bicep' = {
  name: 'vm-spoke1'
  params: {
    name: '${p}-vm1'
    location: location
    subnetId: spoke1.outputs.subnetIds.vms
    adminSshPublicKey: adminSshPublicKey
  }
}

module vm2 'modules/vm-linux.bicep' = {
  name: 'vm-spoke2'
  params: {
    name: '${p}-vm2'
    location: location
    subnetId: spoke2.outputs.subnetIds.vms
    adminSshPublicKey: adminSshPublicKey
  }
}

module vm3 'modules/vm-linux.bicep' = {
  name: 'vm-indirect'
  params: {
    name: '${p}-vm3'
    location: location
    subnetId: indirect.outputs.subnetIds.vms
    adminSshPublicKey: adminSshPublicKey
  }
}

// =====================
// Outputs
// =====================
output vwanName string = vwan.outputs.name
output hub1Name string = hub1.outputs.name
output hub2Name string = hub2.outputs.name
output spoke2AzfwPrivateIp string = spoke2Fw.outputs.privateIp
output spoke2AzfwPublicIp string = spoke2Fw.outputs.publicIp
output vm1PublicIp string = vm1.outputs.publicIp
output vm2PublicIp string = vm2.outputs.publicIp
output vm3PublicIp string = vm3.outputs.publicIp
output vm1PrivateIp string = vm1.outputs.privateIp
output vm2PrivateIp string = vm2.outputs.privateIp
output vm3PrivateIp string = vm3.outputs.privateIp

param name string
param location string

resource policy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: name
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
  }
}

resource ruleCollection 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'lab-allow'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-spoke-traffic'
        priority: 1000
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'allow-rfc1918'
            ipProtocols: [ 'Any' ]
            sourceAddresses: [ '10.0.0.0/8' ]
            destinationAddresses: [ '10.0.0.0/8' ]
            destinationPorts: [ '*' ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'allow-internet-out'
            ipProtocols: [ 'Any' ]
            sourceAddresses: [ '10.0.0.0/8' ]
            destinationAddresses: [ '*' ]
            destinationPorts: [ '*' ]
          }
        ]
      }
    ]
  }
}

output id string = policy.id

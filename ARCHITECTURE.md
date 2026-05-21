# vwan-sr Architecture

## Topology Overview

```mermaid
flowchart TB
  subgraph VWAN["Azure Virtual WAN (Standard)"]
    direction LR
    subgraph HUB1["🛡️ Hub1 — 10.10.0.0/23<br/>(Secured: AzFW in hub)"]
      AZFW1["Azure Firewall<br/>AZFW_Hub SKU<br/>policy: lab-allow"]
      RT1["defaultRouteTable<br/><b>static route:</b><br/>10.0.0.0/8 → AzFW"]
    end
    subgraph HUB2["Hub2 — 10.11.0.0/23<br/>(Plain hub, no firewall)"]
      RT2["defaultRouteTable<br/>(no static routes)"]
    end
    HUB1 <==>|"hub-to-hub<br/>(branch-to-branch on)"| HUB2
  end

  subgraph S1["spoke1 VNet — 10.20.0.0/16"]
    VM1["vm1 (Ubuntu)<br/>10.20.1.x"]
  end

  subgraph S2["spoke2 VNet — 10.30.0.0/16"]
    AZFW2["🔥 Spoke AzFW<br/>AZFW_VNet SKU<br/>10.30.0.x"]
    VM2["vm2 (Ubuntu)<br/>10.30.1.x"]
  end

  subgraph IND["indirect VNet — 10.40.0.0/16<br/>(peered behind spoke2)"]
    VM3["vm3 (Ubuntu)<br/>10.40.1.x"]
  end

  HUB1 ---|"connection: to-spoke1"| S1
  HUB2 ---|"connection: to-spoke2<br/><b>static route:</b><br/>10.40.0.0/16 → 10.30.1.4<br/>propagateStaticRoutes=true"| S2
  S2 <-->|"VNet peering"| IND

  classDef hub fill:#0a4275,stroke:#1f6feb,color:#fff
  classDef spoke fill:#1a3e1a,stroke:#3fb950,color:#fff
  classDef fw fill:#6e2020,stroke:#f85149,color:#fff
  class HUB1,HUB2 hub
  class S1,S2,IND spoke
  class AZFW1,AZFW2 fw
```

## Static Route Demonstrations

### Use Case 1 — AzFW in hub (Hub1)

```mermaid
flowchart LR
  VM1["vm1 in spoke1<br/>10.20.1.x"] -->|"1. ICMP 10.30.1.x"| H1[Hub1]
  H1 -->|"2. static route<br/>10.0.0.0/8 → AzFW"| AZFW1["Hub1 AzFW<br/>inspects + logs"]
  AZFW1 -->|"3. forward"| H1
  H1 -->|"4. hub-to-hub"| H2[Hub2]
  H2 -->|"5. spoke2 connection"| VM2["vm2 in spoke2<br/>10.30.1.x"]
```

- vm1 → vm2 traffic transits Hub1 AzFW for inspection.
- Routing intent must be **disabled** for this pattern (using static routes in hub route table).

### Use Case 2 — NVA (AzFW) in spoke (Hub2 → indirect)

```mermaid
flowchart LR
  VM2["vm2 in spoke2"] -->|"1. ICMP 10.40.1.x"| H2[Hub2]
  H2 -->|"2. connection static route<br/>10.40.0.0/16 → 10.30.1.4"| AZFW2["spoke2 AzFW<br/>10.30.1.4 (NVA)"]
  AZFW2 -->|"3. VNet peering"| VM3["vm3 in indirect VNet<br/>10.40.1.x"]
```

- Static route lives on the **Hub2→spoke2 VNet connection**, next-hop = spoke2 AzFW private IP.
- `propagateStaticRoutes = true` advertises 10.40/16 back to Hub2's route tables → other connections inherit it.
- This is **Option 1** in the MS docs and is **compatible with routing intent** (we don't enable it here, but you could).

### Combined hybrid flow (vm1 → vm3)

```mermaid
flowchart LR
  VM1[vm1<br/>spoke1] -->|"10.40.1.x"| H1[Hub1]
  H1 -->|"static route<br/>10.0.0.0/8 → AzFW"| AZFW1["Hub1 AzFW"]
  AZFW1 --> H1
  H1 -->|"hub-to-hub"| H2[Hub2]
  H2 -->|"static route<br/>10.40/16 → 10.30.1.4"| AZFW2["spoke2 AzFW"]
  AZFW2 -->|"peering"| VM3[vm3<br/>indirect]
```

Two firewalls in series — Hub1 AzFW (hub-attached) inspects east-west, spoke2 AzFW (spoke-deployed NVA) acts as next-hop into the indirect spoke.

## Address Plan

| Resource | CIDR | Notes |
|---|---|---|
| Hub1 | 10.10.0.0/23 | secured w/ AzFW |
| Hub2 | 10.11.0.0/23 | plain |
| spoke1 | 10.20.0.0/16 | vms subnet 10.20.1.0/24 |
| spoke2 | 10.30.0.0/16 | AzureFirewallSubnet 10.30.0.0/26, vms 10.30.1.0/24 |
| indirect | 10.40.0.0/16 | vms 10.40.1.0/24, peered to spoke2 |

## Key Design Choices vs Routing Intent

| Pattern | Used in Lab | Compatible with Routing Intent? |
|---|---|---|
| Static route in hub route table → AzFW resource ID | ✅ Hub1 | ❌ No (mutually exclusive) |
| Static route on VNet connection → IP, `propagate=true` | ✅ Hub2 → spoke2 | ✅ Yes (Option 1) |
| Static route in hub route table → VNet connection + matching IP on connection | ❌ Not used | ❌ No (Option 2) |
| NVA inside the vWAN hub | ❌ Not used | requires Routing Intent |

See [PLAN.md](./PLAN.md) for the full design rationale and the MS doc summary.

# vWAN Static Routes Lab — Plan

Lab to demonstrate **Azure Virtual WAN static routes** per
<https://learn.microsoft.com/en-us/azure/virtual-wan/static-routes>.

## Doc summary (key items)

- **Static routes** in vWAN direct traffic to a specific next-hop. Two primary use cases:
  1. **Route traffic through Azure Firewall** in a secured hub (without routing intent).
  2. **Route traffic to an IP** (NVA/LB) in a spoke VNet.
- **NOT supported via static routes**: directing traffic to an NVA/SaaS deployed *inside* the vWAN hub — that requires **routing intent & policies**.
- **Two use case configs**:
  - **AzFW in hub** → static route in hub route table, next hop = AzFw resource ID. Manage `associations` + `propagations` on connections. Routing intent must be **disabled** for the static-route AzFW pattern.
  - **NVA in spoke** → either (Option 1) static route on the VNet connection with `Propagate static route = true` (preferred, scales, compatible with routing intent), or (Option 2) static route in vWAN route table with next hop = hub VNet connection + matching next-hop IP on the connection (needed for on-prem-to-VNet inspection, **not** compatible with routing intent).
- **Best practices**:
  - Minimise custom route tables; prefer `defaultRouteTable` + `noneRouteTable`.
  - Use **aggregate prefixes** in static routes where possible.
  - Branches (VPN/ER) should all associate to `defaultRouteTable` and propagate to the same tables/labels.
  - Ensure symmetry — if A propagates to B's table, B should propagate to A's.
  - Non-RFC1918 static routes must all share the same next-hop IP.
  - `bypass next-hop IP` setting matters for NVA management traffic.
- **Unsupported / use routing intent instead**:
  - NVA inspection inside the hub.
  - Inter-hub traffic inspection.
  - Branch-to-branch inspection.
  - VNet isolation guarantees (use AzFW network rules).
- **Combined pattern**: AzFW in hub for east-west + NVA in spoke for internet egress (hybrid).

## Lab Goal

Two-hub vWAN with **asymmetric capabilities** to make static-route behaviour observable:

- **Hub1 (secured)** — Azure Firewall in hub, no routing intent. Demonstrates Use Case 1.
- **Hub2 (plain)** — no firewall in hub. **Azure Firewall deployed in spoke2** acts as the inspection point. Demonstrates Use Case 2 (static route to NVA/firewall in spoke).
- One spoke VNet per hub, plus an "indirect spoke" peered behind Hub2's NVA to demo Option 1.

## Target Architecture

```
                       ┌──────────── vWAN (Standard) ───────────┐
                       │                                        │
   spoke1-vnet ◄──────►│  Hub1 (10.10.0.0/23, AzFW secured)    │
   10.20.0.0/16        │  AzFW: 10.10.0.4                       │
                       │            ▲                           │
   demo-vm1 in spoke1  │            │ hub-to-hub                │
                       │            ▼                           │
   spoke2-vnet ◄──────►│  Hub2 (10.11.0.0/23, no firewall)     │
   10.30.0.0/16        │                                        │
   AzFW in spoke2      └────────────────────────────────────────┘
   10.30.1.4 (AzFW)
                              │
                       peered │ (indirect spoke)
                              ▼
                  indirect-vnet 10.40.0.0/16
                  10.40.0.4 (demo-vm3)
```

### Static routes to demonstrate

1. **Hub1 defaultRouteTable**: `10.20.0.0/16` (and `0.0.0.0/0`) → next hop **AzFw resource id**.
   Spoke1 ↔ Spoke2 traffic transits AzFW; AzFW logs prove inspection. Spoke1 ↔ internet via AzFW.
2. **Hub2 VNet connection (spoke2)**: `10.40.0.0/16` with next hop `10.30.1.4` (spoke2 AzFW private IP), `Propagate static route = true` → Option 1. Indirect spoke is reachable from Hub1 via Hub2 → spoke2 AzFW → peered indirect VNet.
3. **Combined**: from spoke1, `10.40.0.0/16` resolves via Hub1 AzFW → Hub2 → spoke2 AzFW → indirect spoke. Validates **two-firewall hybrid**: hub-attached AzFW + spoke-deployed AzFW.

### Validation

- `az network vhub get-effective-routes` on each hub.
- ICMP/TCP from demo-vm1 → demo-vm2 → indirect demo-vm3.
- AzFW logs in Log Analytics to confirm Hub1 inspection.
- `tracepath` to show NVA as intermediate hop for Hub2 path.

## Repo Layout (target)

```
/                    repo root
├─ README.md          (overview + deploy commands)
├─ PLAN.md            (this file)
├─ main.bicep         (top-level orchestration, 2-hub topology)
├─ modules/
│  ├─ vwan.bicep
│  ├─ vhub.bicep
│  ├─ azfw.bicep                (hub-attached AzFW for Hub1)
│  ├─ hub-vnet-connection.bicep (with optional propagateStaticRoutes + staticRoutes)
│  ├─ hub-route-table.bicep     (defaultRouteTable static-route patcher)
│  ├─ spoke-vnet.bicep          (spoke + NSG + VM optional)
│  ├─ vm-linux.bicep            (demo Ubuntu VMs w/ tools: traceroute, mtr)
│  └─ peering.bicep             (spoke2 ↔ indirect-spoke)
├─ scripts/
│  ├─ deploy.sh                 (az deployment group create --no-wait)
│  ├─ verify-routes.sh          (effective routes per hub + per NIC)
│  └─ destroy.sh                (rg delete --no-wait)
└─ docs/
   ├─ use-case-1-azfw.md
   ├─ use-case-2-spoke-nva.md
   └─ combined-hybrid.md
```

## Bicep API versions to target

- `Microsoft.Network/virtualWans@2024-05-01`
- `Microsoft.Network/virtualHubs@2024-05-01`
- `Microsoft.Network/azureFirewalls@2024-05-01`
- `Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01` (supports `routingConfiguration.vnetRoutes.staticRoutes` + `staticRoutesConfig.propagateStaticRoutes`)
- `Microsoft.Network/virtualHubs/hubRouteTables@2024-05-01`

## Deployment plan (phased)

1. **Phase 0 — scaffold** (this PR): PLAN.md + folder layout, no Azure changes.
2. **Phase 1 — refactor**: move existing flat .bicep into `modules/`, bump API versions, drop the 3rd hub, parameterise.
3. **Phase 2 — spokes + VMs**: add spoke VNets, VMs (Bastion-less, JIT-only public IP on one jump VM), peering for indirect spoke.
4. **Phase 3 — static routes**: wire Hub1 AzFW static routes + Hub2 VNet-connection static routes with propagate=true.
5. **Phase 4 — validation scripts + docs**: capture `get-effective-routes` output, tracepaths, AzFW logs.
6. **Phase 5 — teardown**: `destroy.sh` + lab-tracker entry.

## Cost estimate (Australia East, rough)

- vWAN base: free
- 2× vHub units (1 RU each): ~$0.50/hr → ~$24/day for both hubs
- AzFW Standard (hub-attached): ~$1.25/hr + $0.016/GB → ~$30/day idle
- 3× B2s Linux VMs + disks (no Bastion, SSH from home IP only): ~$4/day
- **Spoke AzFW Standard**: ~$30/day idle + data
- **All-up ~$85–90/day** (2× AzFW + 2× vHubs + VMs). Deallocate both AzFWs + VMs when idle → ~$25/day.
- Cost-saver swap: replace spoke AzFW with a Linux NVA VM (iptables/FRR) → drops spoke-side cost to ~$2/day.

## Decisions (locked 2026-05-21)

- **No Bastion** — Linux VMs with public IPs, SSH locked to home IP `115.70.58.97` via NSG.
- **No VPN gateway** — VNet-only topology.
- **Firewall in the spoke VNet** — spoke2 hosts an **Azure Firewall (Standard)** that serves as the next-hop NVA for the static-route demo. This lets the lab compare a **hub-attached AzFW (Hub1)** against a **spoke-deployed AzFW (Hub2 spoke)** side-by-side.

Next: Phase 1 bicep refactor.

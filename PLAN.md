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
- **Hub2 (plain)** — no firewall. Demonstrates Use Case 2 (static route to spoke NVA).
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
   nva-vm in spoke2    └────────────────────────────────────────┘
   10.30.1.4
                              │
                       peered │ (indirect spoke)
                              ▼
                  indirect-vnet 10.40.0.0/16
                  10.40.0.4 (demo-vm3)
```

### Static routes to demonstrate

1. **Hub1 defaultRouteTable**: `10.20.0.0/16` (and `0.0.0.0/0`) → next hop **AzFw resource id**.
   Spoke1 ↔ Spoke2 traffic transits AzFW; AzFW logs prove inspection. Spoke1 ↔ internet via AzFW.
2. **Hub2 VNet connection (spoke2)**: `10.40.0.0/16` with next hop `10.30.1.4` (NVA), `Propagate static route = true` → Option 1. Indirect spoke is reachable from Hub1 via Hub2→NVA→peered VNet.
3. **Combined**: from spoke1, `10.40.0.0/16` resolves via AzFW (Hub1) → Hub2 → NVA → indirect spoke. Validates hybrid pattern.

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
- 3× B2s VMs + disks + Bastion (optional): ~$5/day
- **All-up ~$55–60/day**. Deallocate VMs + AzFW when not demoing to drop to ~$25/day (hubs only).

## Open questions for Nirmal

1. Want **Bastion** for VM access, or stick with JIT public IP on a single jump host? (Bastion Developer SKU ~$free during preview windows but adds complexity.)
2. Include a **VPN gateway** on Hub2 to also demonstrate branch→spoke-via-static-route, or keep it VNet-only for now?
3. Should we also include a **routing intent** comparison hub later (Hub3), to contrast against static routes?

— answer those and I'll proceed to Phase 1.

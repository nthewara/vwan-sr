# vwan-sr — Azure Virtual WAN Static Routes Lab

Bicep lab demonstrating **[Azure Virtual WAN static routes](https://learn.microsoft.com/en-us/azure/virtual-wan/static-routes)** — both use cases, side by side.

- **Hub1** — secured with a **hub-attached Azure Firewall**, demonstrates **Use Case 1** (static route in hub route table → AzFW resource ID).
- **Hub2** — plain hub, with an **Azure Firewall deployed in spoke2** acting as the NVA, demonstrates **Use Case 2 / Option 1** (static route on the VNet connection → NVA IP, `propagateStaticRoutes = true`).
- An **indirect spoke** is VNet-peered behind spoke2 so traffic from Hub2 to `10.40.0.0/16` is forced through the spoke AzFW.

> 📐 See **[ARCHITECTURE.md](./ARCHITECTURE.md)** for Mermaid diagrams of the topology + traffic flows.
> 📄 See **[PLAN.md](./PLAN.md)** for the design plan, MS-docs summary, and the routing-intent compatibility notes.

## Address plan

| Resource | CIDR | Notes |
|---|---|---|
| Hub1 | `10.10.0.0/23` | secured with AzFW (AZFW_Hub) |
| Hub2 | `10.11.0.0/23` | plain hub |
| spoke1 | `10.20.0.0/16` | vm1 in `10.20.1.0/24` |
| spoke2 | `10.30.0.0/16` | spoke AzFW in `10.30.0.0/26`, vm2 in `10.30.1.0/24` |
| indirect | `10.40.0.0/16` | vm3 in `10.40.1.0/24`, peered to spoke2 |

## Repo layout

```
.
├── main.bicep                        top-level orchestration
├── modules/
│   ├── vwan.bicep
│   ├── vhub.bicep
│   ├── hub-azfw.bicep                AZFW_Hub SKU (Hub1)
│   ├── fw-policy.bicep               shared lab-allow firewall policy
│   ├── spoke-vnet.bicep              VNet + NSG (+ AzureFirewallSubnet on spoke2)
│   ├── spoke-azfw.bicep              AZFW_VNet SKU NVA (spoke2)
│   ├── hub-vnet-connection.bicep     hub↔VNet connection (+ optional static routes)
│   ├── peering.bicep                 VNet peering (spoke2 ↔ indirect)
│   └── vm-linux.bicep                Ubuntu 24.04 + public IP, SSH-locked to home IP
├── scripts/deploy.sh                 deploy helper (PHASE=A|B)
├── PLAN.md
└── ARCHITECTURE.md
```

## Two-phase deployment

The deployment is **two-phased** because vWAN hub VNet connections need to exist before you can attach static routes to them.

### Phase A — infrastructure

Provisions: vWAN, Hub1 + Hub2, hub-attached AzFW (Hub1), shared firewall policy, 3 spoke VNets, spoke2 AzFW, VNet peering (spoke2 ↔ indirect), 3 Ubuntu VMs, and the two hub→VNet connections **without** static routes.

```bash
# create an SSH key once
ssh-keygen -t ed25519 -f ~/.ssh/vwansr_ed25519 -N ''

# create RG
RG=vwan-sr-$(openssl rand -hex 2)
az group create -n $RG -l australiaeast

# Phase A
RG=$RG PHASE=A ./scripts/deploy.sh
```

Wait until both hub VNet connections show `provisioningState=Succeeded`:

```bash
for h in $(az network vhub list -g $RG --query "[].name" -o tsv); do
  az network vhub connection list --vhub-name $h -g $RG \
    --query "[].{n:name,s:provisioningState}" -o tsv
done
```

⚠️ **Known vWAN quirk**: hub connections can transiently end up `Failed` with a stuck async-op error (`Operation … not found`). If that happens, delete the failed connection and recreate via CLI:

```bash
az network vhub connection delete --vhub-name <hub> -g $RG -n <conn> --no-wait -y
az network vhub connection create --vhub-name <hub> -g $RG -n <conn> \
  --remote-vnet $(az network vnet show -g $RG -n <spoke-vnet> --query id -o tsv)
```

### Phase B — static routes

Re-runs the same template with `enableStaticRoutes=true`, which adds:

| Where | Route | Next hop |
|---|---|---|
| Hub1 `defaultRouteTable` | `10.0.0.0/8` | Hub1 AzFW resource ID |
| Hub2 → spoke2 connection | `10.40.0.0/16` | `10.30.1.4` (spoke2 AzFW), `propagate=true` |

```bash
RG=$RG PHASE=B ./scripts/deploy.sh
```

## Validation

```bash
# effective routes on each hub
az network vhub get-effective-routes -g $RG --name <hub-name> \
  --resource-type RouteTable --resource-id <hub-defaultRouteTable-id>

# from vm1 (spoke1) -> vm2 (spoke2) should transit Hub1 AzFW
ssh azureuser@<vm1-pip> -i ~/.ssh/vwansr_ed25519 \
  'sudo apt-get install -y traceroute && traceroute -n <vm2-private-ip>'

# from vm2 (spoke2) -> vm3 (indirect) should transit spoke2 AzFW (10.30.1.4)
ssh azureuser@<vm2-pip> -i ~/.ssh/vwansr_ed25519 \
  'traceroute -n <vm3-private-ip>'
```

VM public IPs are output by the deployment:

```bash
az deployment group show -g $RG -n vwansr-phase-B \
  --query properties.outputs -o json
```

## Routing-intent compatibility

| Pattern | Used in this lab | Compatible with Routing Intent |
|---|---|---|
| Static route in hub route table → AzFW resource ID | ✅ Hub1 | ❌ |
| Static route on VNet connection → IP, `propagate=true` (Option 1) | ✅ Hub2→spoke2 | ✅ |
| Static route in hub route table → VNet connection (Option 2) | ❌ | ❌ |

> The Hub1 pattern and routing intent are mutually exclusive on a hub. Hub2's connection-level static route is the routing-intent-friendly option.

## Cost (rough, australiaeast)

- 2× vHub units: ~$24/day
- Hub-attached AzFW (Standard): ~$30/day
- Spoke AzFW (Standard): ~$30/day
- 3× B1s Ubuntu VMs + disks: ~$3/day
- **~$85–90/day all-up.** Delete the RG to stop the meter.

## Tear down

```bash
az group delete -n $RG --no-wait -y
```

## Status

✅ Phase A and Phase B both deployed successfully on `australiaeast`. Lab is live and ready for static-route demos.

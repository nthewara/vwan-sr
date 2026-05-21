# vwan-sr — Azure Virtual WAN Static Routes Lab

Bicep lab demonstrating **[Azure Virtual WAN static routes](https://learn.microsoft.com/en-us/azure/virtual-wan/static-routes)**.

**Topology**
- vWAN (Standard) with **two hubs** in `australiaeast`
  - **Hub1** — secured with **Azure Firewall** (no routing intent) → demos Use Case 1
  - **Hub2** — plain hub, no firewall → demos Use Case 2 (static route to NVA in spoke)
- Spoke VNets per hub + an indirect spoke peered behind the Hub2 NVA

See **[PLAN.md](./PLAN.md)** for full architecture, phased delivery plan, and validation steps.
See **[ARCHITECTURE.md](./ARCHITECTURE.md)** for diagrams (Mermaid).

## Deploy (planned)
```bash
rg=vwansr-$RANDOM
az group create -n $rg -l australiaeast
az deployment group create -g $rg -f main.bicep --parameters prefix=$rg --no-wait
```

## Status
Phase 0 — scaffolding & plan. Bicep modules coming in Phase 1.

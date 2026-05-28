# VM Module 1: Deploy Infrastructure

Run the **Deploy VM Infrastructure** GitHub Actions workflow.

Inputs:
- `location`
- `workloadName` (default `srelabvm`)
- `adminUsername` (default `azureuser`)

The workflow deploys:
- 2 Windows Server VMs with IIS
- B-series VM sizing (`Standard_B2s`) for cost-efficient lab runtime
- Daily auto-shutdown on each VM (UTC 19:00)
- VNet + subnet + NSG
- Azure Bastion host (operator access path)
- Log Analytics + Application Insights
- Managed identity + Reader/Monitoring Reader assignments
- VM-focused scheduled query alerts

After deployment, capture:
- VM names
- VM private IPs
- Bastion host name
- Log Analytics workspace ID

## Access model

This VM track is designed for enterprise-safe access:

- No public RDP exposure on VM NICs
- Operator access through Azure Bastion tunnels

Examples:

```powershell
# HTTP tunnel to VM web workload
.\workshops\vm\scripts\access\start-http-tunnel.ps1 -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -BastionName srelabvm-bas -LocalPort 18080
```

```powershell
# RDP tunnel to VM
.\workshops\vm\scripts\access\start-rdp-tunnel.ps1 -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -BastionName srelabvm-bas -LocalPort 13389 -VmUser azureuser
```


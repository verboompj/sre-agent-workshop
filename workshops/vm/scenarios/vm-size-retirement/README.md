# VM Module 3: Scenario 4 — VM Size Retirement (SKU Discontinuation)

An Azure Service Health advisory announces that the **Dv2/DSv2-series** VM sizes are being retired.
The injector plants three deallocated "legacy" VMs on a retiring size so the SRE Agent can practise
the real task: **identify every affected service under its control** (via Azure Resource Graph) and
migrate it to a current size — all through the approval gate.

## How this fires in production

Azure raises VM size retirements as **Azure Service Health → Health advisories**. In a real
environment a subscription-scoped **Activity Log alert** (`category == ServiceHealth`) routes the
advisory through an **Action Group** to the SRE Agent's incident intake. That production wiring is
shown for reference in [`service-health-alert.bicep`](./service-health-alert.bicep) (an Action
Group + an `activityLogAlerts` resource).

> **Service Health events can't be injected on demand**, so this scenario *simulates* the kickoff:
> `inject` prints a realistic Service Health advisory payload — the same shape Azure would send —
> for you to paste into the agent. Everything after the kickoff (the Resource Graph inventory and
> the approval-gated migration) runs against real resources.

## Inject fault

```bash
./inject.sh --resource-group rg-srelabvm
# PowerShell: pwsh ./inject.ps1 -ResourceGroup rg-srelabvm
```

This creates `srelabvm-legacy-01/02/03` (deallocated, on `Standard_DS1_v2`/`Standard_DS2_v2`) and
prints the Service Health advisory to paste into the agent.

## Kick off the agent

Paste the advisory JSON that `inject` emitted (a committed example is in
[`service-health-advisory.json`](./service-health-advisory.json)) into the SRE Agent and ask it to
identify all affected VMs and prepare the migration.

## Investigation flow

The agent enumerates affected VMs with an Azure Resource Graph query ([`query.kql`](./query.kql)):

```bash
az graph query -q "Resources | where type =~ 'microsoft.compute/virtualMachines' | where resourceGroup =~ 'rg-srelabvm' | extend vmSize = tostring(properties.hardwareProfile.vmSize) | where vmSize in~ ('Standard_DS1_v2','Standard_DS2_v2') | project name, vmSize, tags"
```

Expected: the three `srelabvm-legacy-*` VMs. The `Standard_B2s` baseline VMs
(`srelabvm-vm01`/`srelabvm-vm02`) are not affected.

## Remediate (approval required)

Migration is disruptive (a resize), so it runs only through the approval gate with a CHG/INC ticket:

```powershell
..\..\tools\Invoke-ApprovedRemediation.ps1 -Action migrate-vm-size -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12345
```
```bash
../../tools/invoke-approved-remediation.sh --action migrate-vm-size --change-ticket CHG-12345
```

The `migrate-vm-size` action discovers every VM on a retiring size and resizes it to
`Standard_D2s_v5`, writing an audit entry. (The `-VmName` argument is required by the gate, but the
action migrates the whole affected fleet, not a single VM.)

## Validate

```bash
./validate.sh --resource-group rg-srelabvm
```

Passes when no VM in the resource group remains on a retiring size.

## Next step

See [90. Watch Agent Workflow](../../docs/90-watch-agent-workflow.md).

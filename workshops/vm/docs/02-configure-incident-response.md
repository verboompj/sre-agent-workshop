# VM Module 2: Configure Incident Response

Use the same incident platform pattern as the AKS track:

1. Connect the SRE Agent to **Azure Monitor**.
2. Create an incident response plan scoped to VM workshop alerts.
3. Use **Review-style approvals** for remediation in this VM track.

## Approval-gated execution

Remediation always runs through `Invoke-ApprovedRemediation.ps1`, which requires a CHG/INC ticket and explicit `APPROVE` confirmation, then writes an audit entry. Available actions:

| Action | Scope | Use when |
|--------|-------|----------|
| `cleanup-disk` | Removes only `C:\Temp\diskfill` artifacts | Surgical fix for Scenario 1 |
| `cleanup-temp` | Clears everything under `C:\Temp` | Agent policy forbids arbitrary deletes but allows approved Temp cleanup |
| `start-iis-app-pool` | Restarts the target IIS app pool | Scenario 2 remediation |
| `stop-cpu-runaway` | Stops the sustained CPU workload | Scenario 3 remediation |

Example:

```powershell
.\workshops\vm\tools\Invoke-ApprovedRemediation.ps1 -Action cleanup-disk -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12345
```

No remediation action runs without an approval prompt and valid ticket format.


# VM Module 5: Scenario 3 — CPU Runaway

The injector starts a sustained hidden PowerShell workload so CPU pressure stays high until remediation.

## Inject fault

```powershell
.\workshops\vm\scripts\scenarios\inject-cpu-runaway.ps1 -ResourceGroup rg-srelabvm -VmName srelabvm-vm01
```

## Investigation flow

```powershell
.\workshops\vm\tools\Invoke-VmInvestigation.ps1 -WorkspaceId <LAW_WORKSPACE_ID> -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -Scenario cpu-runaway
```

## Remediate (approval required)

```powershell
.\workshops\vm\tools\Invoke-ApprovedRemediation.ps1 -Action stop-cpu-runaway -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12347
```


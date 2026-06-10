# VM Module 4: Scenario 2 — IIS App Pool Failure

## Inject fault

```powershell
.\inject.ps1 -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -AppPoolName DefaultAppPool
```

## Investigation flow

```powershell
..\..\tools\Invoke-VmInvestigation.ps1 -WorkspaceId <LAW_WORKSPACE_ID> -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -Scenario iis-app-pool
```

## Remediate (approval required)

```powershell
..\..\tools\Invoke-ApprovedRemediation.ps1 -Action start-iis-app-pool -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12346
```


# VM Module 3: Scenario 1 — Disk Full

The injector iteratively fills `C:\Temp\diskfill\*` with 1GB files until the disk is full, so investigation can attribute pressure to the Temp folder.

## Inject fault

```powershell
.\workshops\vm\scripts\scenarios\inject-disk-full.ps1 -ResourceGroup rg-srelabvm -VmName srelabvm-vm01
```

## Investigation flow

```powershell
.\workshops\vm\tools\Invoke-VmInvestigation.ps1 -WorkspaceId <LAW_WORKSPACE_ID> -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -Scenario disk-full
```

## Remediate (approval required)

Two approval-gated options, depending on agent constraints:

```powershell
# Surgical — removes only C:\Temp\diskfill artifacts and stops the fill loop
.\workshops\vm\tools\Invoke-ApprovedRemediation.ps1 -Action cleanup-disk -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12345

# Broader — clears everything under C:\Temp (use when the agent's policy
# forbids deleting arbitrary paths but allows an approved Temp cleanup)
.\workshops\vm\tools\Invoke-ApprovedRemediation.ps1 -Action cleanup-temp -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12348
```


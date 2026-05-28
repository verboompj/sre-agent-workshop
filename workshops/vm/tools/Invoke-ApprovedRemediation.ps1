# Approval-gated remediation wrapper.
# Maps an action name to a constrained remediation script, requires a
# CHG/INC ticket and explicit "APPROVE" confirmation, and writes an audit
# entry per execution. The SRE Agent never runs remediation directly —
# every action passes through this gate.
param(
    [Parameter(Mandatory = $true)][ValidateSet("cleanup-disk", "cleanup-temp", "start-iis-app-pool", "stop-cpu-runaway")][string]$Action,
    [string]$ResourceGroup = "rg-srelabvm",
    [string]$VmName = "srelabvm-vm01",
    [Parameter(Mandatory = $true)][string]$ChangeTicket
)

if ($ChangeTicket -notmatch '^(CHG|INC)-[0-9]+$') {
    throw "ChangeTicket must match CHG-12345 or INC-12345."
}

$actionMap = @{
    "cleanup-disk" = "$PSScriptRoot\..\scripts\remediation\cleanup-disk.ps1"
    "cleanup-temp" = "$PSScriptRoot\..\scripts\remediation\cleanup-temp.ps1"
    "start-iis-app-pool" = "$PSScriptRoot\..\scripts\remediation\start-iis-app-pool.ps1"
    "stop-cpu-runaway" = "$PSScriptRoot\..\scripts\remediation\stop-cpu-runaway.ps1"
}

$scriptPath = $actionMap[$Action]
if (-not (Test-Path $scriptPath)) {
    throw "Approved action script missing: $scriptPath"
}

Write-Host "========================================"
Write-Host "  Approval Gate"
Write-Host "========================================"
Write-Host "Ticket:        $ChangeTicket"
Write-Host "Action:        $Action"
Write-Host "ResourceGroup: $ResourceGroup"
Write-Host "VM:            $VmName"
Write-Host "========================================"
$approval = Read-Host "Type APPROVE to execute"
if ($approval -ne "APPROVE") {
    throw "Remediation canceled. Explicit approval was not granted."
}

& $scriptPath -ResourceGroup $ResourceGroup -VmName $VmName

if (-not (Test-Path "$PSScriptRoot\..\output")) {
    New-Item -Path "$PSScriptRoot\..\output" -ItemType Directory | Out-Null
}

$auditEntry = [PSCustomObject]@{
    timestamp = (Get-Date).ToString("o")
    ticket = $ChangeTicket
    action = $Action
    resourceGroup = $ResourceGroup
    vmName = $VmName
    status = "executed"
}

$auditEntry | ConvertTo-Json -Compress | Add-Content -Path "$PSScriptRoot\..\output\actions-audit.log"
Write-Host "Approved remediation completed and audited."


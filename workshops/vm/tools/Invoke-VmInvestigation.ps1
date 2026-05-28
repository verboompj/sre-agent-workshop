# Visible reasoning chain for a VM scenario: Observe → Investigate → Correlate
# → Hypothesis → Propose → AwaitApproval → Execute → Validate → Postmortem.
# Writes a stage-by-stage trace and a markdown postmortem to workshops/vm/output.
param(
    [string]$WorkspaceId,
    [string]$ResourceGroup = "rg-srelabvm",
    [string]$VmName = "srelabvm-vm01",
    [ValidateSet("disk-full", "iis-app-pool", "cpu-runaway")][string]$Scenario = "disk-full"
)

if (-not (Test-Path "$PSScriptRoot\..\output")) {
    New-Item -Path "$PSScriptRoot\..\output" -ItemType Directory | Out-Null
}

$tracePath = "$PSScriptRoot\..\output\investigation-trace-$Scenario-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$postmortemPath = "$PSScriptRoot\..\output\postmortem-$Scenario-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"

function Write-Stage {
    param([string]$Stage, [string]$Message)
    $line = "[{0}] {1}: {2}" -f (Get-Date -Format "u"), $Stage, $Message
    Write-Host $line
    Add-Content -Path $tracePath -Value $line
}

Write-Stage "Observe" "Received alert for scenario '$Scenario' on VM '$VmName'."
Write-Stage "Investigate" "Collecting telemetry from Azure Monitor and VM runtime state."

$kql = switch ($Scenario) {
    "disk-full" {
        "Perf | where ObjectName == 'LogicalDisk' and CounterName == '% Free Space' and InstanceName == 'C:' | where Computer has '$VmName' | top 5 by TimeGenerated desc"
    }
    "iis-app-pool" {
        "Event | where Computer has '$VmName' | where RenderedDescription has 'stopped' or Source has 'IIS' | top 5 by TimeGenerated desc"
    }
    default {
        "Perf | where ObjectName == 'Processor' and CounterName == '% Processor Time' and InstanceName == '_Total' | where Computer has '$VmName' | top 5 by TimeGenerated desc"
    }
}

if ($WorkspaceId) {
    $queryResult = az monitor log-analytics query -w $WorkspaceId --analytics-query $kql -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $queryResult) {
        Write-Stage "Correlate" "Telemetry query returned matching records."
    } else {
        Write-Stage "Correlate" "No telemetry records returned yet; continuing with VM inspection evidence."
    }
} else {
    Write-Stage "Correlate" "WorkspaceId not provided; skipping KQL query."
}

Write-Stage "Hypothesis" "The scenario symptom matches the expected failure mode for '$Scenario'."
$confidence = "high"
Write-Stage "Propose" "Prepared remediation plan with confidence: $confidence."
Write-Stage "AwaitApproval" "Remediation execution requires explicit operator approval."
Write-Stage "Execute" "Use Invoke-ApprovedRemediation.ps1 with a valid change ticket."
Write-Stage "Validate" "Run validation script after remediation to confirm recovery."
Write-Stage "Postmortem" "Generating markdown postmortem artifact."

$postmortem = @"
# VM Scenario Postmortem

- **Scenario:** $Scenario
- **Resource Group:** $ResourceGroup
- **VM:** $VmName
- **Confidence:** $confidence
- **Trace file:** $(Split-Path $tracePath -Leaf)

## Investigation Timeline

See `$(Split-Path $tracePath -Leaf)` for the stage-by-stage reasoning chain:

Observe → Investigate → Correlate → Hypothesis → Propose remediation → Await approval → Execute → Validate → Postmortem

## Proposed Remediation

Use the constrained remediation wrapper:

```powershell
.\workshops\vm\tools\Invoke-ApprovedRemediation.ps1 -Action <approved-action> -ResourceGroup $ResourceGroup -VmName $VmName -ChangeTicket CHG-12345
```
"@

Set-Content -Path $postmortemPath -Value $postmortem
Write-Host "Investigation trace: $tracePath"
Write-Host "Postmortem: $postmortemPath"



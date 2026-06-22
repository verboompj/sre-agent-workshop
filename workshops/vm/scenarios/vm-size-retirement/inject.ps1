#!/usr/bin/env pwsh
# Scenario — VM Size Retirement (PowerShell variant; mirrors inject.sh).
param(
    [string]$ResourceGroup = "rg-srelabvm",
    [string]$Workload = "srelabvm"
)
# Note: $ErrorActionPreference is deliberately NOT 'Stop' here. This injector
# branches on $LASTEXITCODE from `az vm show` / `az network nic show` returning
# non-zero (the normal "resource does not exist yet" path), mirroring the sibling
# VM injectors. 'Stop' would turn those expected non-zero exits into terminating
# errors when $PSNativeCommandUseErrorActionPreference is enabled.

$vnetName = "$Workload-vnet"
$subnetName = "$Workload-subnet"
$adminUser = "azureuser"
$adminPassword = "Sre" + ([guid]::NewGuid().ToString("N").Substring(0, 16)) + "#Aa9"

$legacyVms = @(
    @{ Name = "$Workload-legacy-01"; Size = "Standard_DS1_v2"; Tags = @("env=prod", "app=billing-legacy", "owner=unknown") },
    @{ Name = "$Workload-legacy-02"; Size = "Standard_DS2_v2"; Tags = @("env=test", "app=reporting-legacy") },
    @{ Name = "$Workload-legacy-03"; Size = "Standard_DS1_v2"; Tags = @("env=prod", "app=batch-legacy", "owner=unknown") }
)

$location = az group show --name $ResourceGroup --query location -o tsv

foreach ($v in $legacyVms) {
    az vm show --resource-group $ResourceGroup --name $v.Name 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Resetting $($v.Name) to retiring size $($v.Size) ..."
        az vm resize --resource-group $ResourceGroup --name $v.Name --size $v.Size --only-show-errors | Out-Null
    }
    else {
        Write-Host "Creating legacy VM $($v.Name) ($($v.Size)) ..."
        az network nic show --resource-group $ResourceGroup --name "$($v.Name)-nic" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            az network nic create --resource-group $ResourceGroup --name "$($v.Name)-nic" `
                --vnet-name $vnetName --subnet $subnetName --only-show-errors | Out-Null
        }
        az vm create `
            --resource-group $ResourceGroup `
            --name $v.Name `
            --image Ubuntu2204 `
            --size $v.Size `
            --nics "$($v.Name)-nic" `
            --storage-sku StandardSSD_LRS `
            --admin-username $adminUser `
            --admin-password $adminPassword `
            --authentication-type password `
            --tags $v.Tags workshop=sre-agent track=vm scenario=vm-size-retirement `
            --only-show-errors --no-wait | Out-Null
    }
}

foreach ($v in $legacyVms) {
    az vm wait --resource-group $ResourceGroup --name $v.Name --created --only-show-errors 2>$null | Out-Null
    az vm deallocate --resource-group $ResourceGroup --name $v.Name --no-wait --only-show-errors 2>$null | Out-Null
}

$subscriptionId = az account show --query id -o tsv
$retirementDate = "2027-05-31"
$trackingId = "0BNF-9X8"
$eventTs = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$advisory = @"
{
  "eventSource": "ServiceHealth",
  "category": "ServiceHealth",
  "level": "Warning",
  "operationName": "Microsoft.ServiceHealth/healthadvisory/action",
  "eventTimestamp": "$eventTs",
  "properties": {
    "title": "Action required: migrate off retiring Dv2/DSv2-series virtual machine sizes",
    "service": "Virtual Machines",
    "region": "$location",
    "incidentType": "ActionRequired",
    "trackingId": "$trackingId",
    "impactedService": "Virtual Machines",
    "impactedSizes": "Standard_DS1_v2 / Standard_DS2_v2 (DSv2-series)",
    "retirementDate": "$retirementDate",
    "subscriptionId": "$subscriptionId",
    "communication": "The Dv2/DSv2-series VM sizes are being retired on $retirementDate. Identify all virtual machines in your control on these sizes and resize them to a current series (for example Standard_D2s_v5) before the retirement date to avoid service disruption."
  }
}
"@

Write-Host ""
Write-Host "================================================================"
Write-Host "Paste the following Azure Service Health advisory into the SRE Agent:"
Write-Host "================================================================"
Write-Host $advisory
Write-Host "================================================================"
Write-Host "Legacy VMs planted in ${ResourceGroup}: $Workload-legacy-01, $Workload-legacy-02, $Workload-legacy-03"

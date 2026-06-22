#!/usr/bin/env pwsh
param([string]$ResourceGroup = "rg-srelabapp", [string]$Workload = "srelabapp", [string]$Slot = "staging")
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = Join-Path $scriptDir "../../src"

$web = az webapp list -g $ResourceGroup --query "[?starts_with(name,'$Workload-web-')].name | [0]" -o tsv
if (-not $web) { throw "No web app found in $ResourceGroup" }

az webapp traffic-routing clear -g $ResourceGroup --name $web
Write-Host "Cleared traffic routing: 100% to the production slot on $web."

$buildDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid()))
try {
    Copy-Item -Recurse -Force "$srcDir/*" $buildDir
    dotnet publish (Join-Path $buildDir "Shop.csproj") -c Release -o (Join-Path $buildDir "publish")
    Compress-Archive -Path (Join-Path $buildDir "publish/*") -DestinationPath (Join-Path $buildDir "app.zip") -Force
    az webapp deploy -g $ResourceGroup --name $web --slot $Slot --type zip --src-path (Join-Path $buildDir "app.zip")
    Write-Host "Remediation complete: traffic cleared and the good build redeployed to slot '$Slot'."
} finally {
    Remove-Item -Recurse -Force $buildDir
}

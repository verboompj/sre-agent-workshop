#!/usr/bin/env pwsh
param([string]$ResourceGroup = "rg-srelabapp", [string]$Workload = "srelabapp", [string]$Slot = "staging")
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = Join-Path $scriptDir "../../src"

$web = az webapp list -g $ResourceGroup --query "[?starts_with(name,'$Workload-web-')].name | [0]" -o tsv
if (-not $web) { throw "No web app found in $ResourceGroup" }

$buildDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid()))
try {
    Copy-Item -Recurse -Force "$srcDir/*" $buildDir
    Copy-Item -Force (Join-Path $scriptDir "Program.regression.cs") (Join-Path $buildDir "Program.cs")
    dotnet publish (Join-Path $buildDir "Shop.csproj") -c Release -o (Join-Path $buildDir "publish")
    Compress-Archive -Path (Join-Path $buildDir "publish/*") -DestinationPath (Join-Path $buildDir "app.zip") -Force
    az webapp deploy -g $ResourceGroup --name $web --slot $Slot --type zip --src-path (Join-Path $buildDir "app.zip")
    az webapp traffic-routing set -g $ResourceGroup --name $web --distribution "$Slot=50"
    Write-Host "Fault injected: bad v2 release on slot '$Slot' with 50% canary traffic on $web."
} finally {
    Remove-Item -Recurse -Force $buildDir
}

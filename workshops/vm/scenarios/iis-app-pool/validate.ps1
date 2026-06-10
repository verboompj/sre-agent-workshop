#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\..\..\scripts\validation\smoke-test.ps1" @args

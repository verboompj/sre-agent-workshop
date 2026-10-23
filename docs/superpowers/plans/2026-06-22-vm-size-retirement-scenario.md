# VM Size Retirement Scenario Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-contained VM-track scenario `vm-size-retirement` where a simulated Azure Service Health advisory drives the SRE Agent to identify (via Azure Resource Graph) every VM in its resource group on a retiring size and migrate them via the approval gate.

**Architecture:** A scaffolded scenario folder under `workshops/vm/scenarios/vm-size-retirement/`. `inject` plants 3 deallocated "legacy" Ubuntu VMs on retiring DSv2 sizes and emits a Service Health advisory JSON to paste into the agent. The agent enumerates affected VMs with an ARG query; an approval-gated `migrate-vm-size` action resizes them to `Standard_D2s_v5`; `validate` confirms none remain. No wired alert (`signal` omitted, `alert.bicep` deleted); the production Service Health wiring ships as a non-wired reference `service-health-alert.bicep` plus a README notice.

**Tech Stack:** Bash + PowerShell (`az` CLI) scripts, Bicep, YAML manifest, the repo's Node ESM scenario tooling (`scripts/scenario-tools`).

**Spec:** `docs/superpowers/specs/2026-06-22-vm-size-retirement-scenario-design.md`

**Constants used throughout (do not vary):**
- Track: `vm`; scenario id/folder: `vm-size-retirement`
- Resource group default: `rg-srelabvm`; workload default: `srelabvm`
- Existing network: VNet `srelabvm-vnet`, subnet `srelabvm-subnet`
- Baseline VMs (excluded): `srelabvm-vm01`, `srelabvm-vm02` (`Standard_B2s`)
- Retiring sizes: `Standard_DS1_v2`, `Standard_DS2_v2`
- Migration target: `Standard_D2s_v5`
- Legacy VMs: `srelabvm-legacy-01` (DS1_v2), `srelabvm-legacy-02` (DS2_v2), `srelabvm-legacy-03` (DS1_v2)

---

## File map

Created under `workshops/vm/scenarios/vm-size-retirement/`:
- `scenario.yaml` — manifest (no `signal`)
- `inject.sh` / `inject.ps1` — plant legacy VMs + emit advisory
- `service-health-advisory.json` — committed example advisory payload
- `query.kql` — Azure Resource Graph inventory query
- `migrate-vm-size.sh` / `migrate-vm-size.ps1` — approval-gated resize migration
- `validate.sh` / `validate.ps1` — pass when no VM on a retiring size
- `service-health-alert.bicep` — production wiring reference (NOT wired/deployed)
- `README.md` — attendee walkthrough + "How this fires in production" notice

Deleted from the scaffold: `alert.bicep`, `remediate.sh`, `remediate.ps1`.

Modified (shared):
- `workshops/vm/scenarios/INDEX.md` — regenerated (gains a row)
- `workshops/vm/README.md` — regenerated scenario table (gains a row)
- `workshops/vm/docs/02-configure-incident-response.md` — add `migrate-vm-size` to the actions table

Unchanged (verify no drift): `workshops/vm/infra/bicep/modules/scenario-alerts.bicep`.

---

### Task 1: Scaffold the scenario and prune unused files

**Files:**
- Create (scaffold): `workshops/vm/scenarios/vm-size-retirement/` (whole folder)
- Delete: `.../alert.bicep`, `.../remediate.sh`, `.../remediate.ps1`

- [ ] **Step 1: Scaffold from the template**

Run:
```bash
scripts/new-scenario.sh vm vm-size-retirement "VM Size Retirement (SKU Discontinuation)"
```
Expected: `Created vm/vm-size-retirement at .../workshops/vm/scenarios/vm-size-retirement` and the folder contains `scenario.yaml inject.sh inject.ps1 validate.sh validate.ps1 remediate.sh remediate.ps1 alert.bicep query.kql README.md`.

- [ ] **Step 2: Delete the files this scenario does not use**

This scenario has no wired alert (the kickoff is the simulated advisory) and renames the remediation, so remove the scaffolded `alert.bicep` and `remediate.*`:
```bash
cd workshops/vm/scenarios/vm-size-retirement
rm alert.bicep remediate.sh remediate.ps1
cd -
```
Expected: those three files are gone; `scenario.yaml inject.sh inject.ps1 validate.sh validate.ps1 query.kql README.md` remain.

- [ ] **Step 3: Commit**

```bash
git add -A workshops/vm/scenarios/vm-size-retirement
git commit -m "chore(vm): scaffold vm-size-retirement scenario (alert-less)"
```

---

### Task 2: Author the manifest (`scenario.yaml`)

**Files:**
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/scenario.yaml`

- [ ] **Step 1: Replace the file contents**

Replace `workshops/vm/scenarios/vm-size-retirement/scenario.yaml` with exactly:
```yaml
id: vm-size-retirement
title: VM Size Retirement (SKU Discontinuation)
track: vm
summary: An Azure Service Health advisory announces a VM size retirement; the agent uses Azure Resource Graph to identify every VM in its resource group on a retiring size and migrates them to a current family via the approval gate.
severity: 2
estimatedMinutes: 30
difficulty: intermediate
learningObjectives:
  - Read an Azure Service Health "service retirement" advisory and extract the affected SKU and deadline.
  - Use Azure Resource Graph to identify all affected services under the agent's control (every VM on a retiring size in the resource group).
  - Migrate affected VMs to a current size by resize, executed only through the approval gate with a CHG/INC ticket and audit entry.
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: migrate-vm-size
    bash: migrate-vm-size.sh
    powershell: migrate-vm-size.ps1
    description: Resize every VM in the resource group that is on a retiring size to the current target size (Standard_D2s_v5).
investigation:
  query: query.kql
docPage: README.md
```

Note: there is **no `signal:` block** — this is intentional (the scenario has no wired alert).

- [ ] **Step 2: Sanity-check the YAML parses and has no `signal`**

Run:
```bash
node -e "const y=require('js-yaml');" 2>/dev/null; grep -q '^signal:' workshops/vm/scenarios/vm-size-retirement/scenario.yaml && echo 'UNEXPECTED signal present' || echo 'OK: no signal block'
```
Expected: `OK: no signal block`.

- [ ] **Step 3: Commit**

```bash
git add workshops/vm/scenarios/vm-size-retirement/scenario.yaml
git commit -m "feat(vm): vm-size-retirement manifest (no wired alert, migrate-vm-size action)"
```

---

### Task 3: Author the injector and advisory inputs

**Files:**
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/inject.sh`
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/inject.ps1`
- Create: `workshops/vm/scenarios/vm-size-retirement/service-health-advisory.json`
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/query.kql`

- [ ] **Step 1: Write `inject.sh`**

Replace `workshops/vm/scenarios/vm-size-retirement/inject.sh` with exactly:
```bash
#!/usr/bin/env bash
# Scenario — VM Size Retirement.
# Plants 3 deallocated "legacy" VMs on a retiring DSv2 size so the SRE Agent can
# enumerate every affected VM in the resource group, then emits a simulated Azure
# Service Health retirement advisory for the attendee to paste into the agent.
set -euo pipefail

RESOURCE_GROUP="rg-srelabvm"
WORKLOAD="srelabvm"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -w|--workload) WORKLOAD="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>] [--workload <name>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

VNET_NAME="${WORKLOAD}-vnet"
SUBNET_NAME="${WORKLOAD}-subnet"
ADMIN_USER="azureuser"
ADMIN_PASSWORD="Sre$(openssl rand -hex 12)#Aa9"

# name|size|space-separated tags
LEGACY_VMS="
${WORKLOAD}-legacy-01|Standard_DS1_v2|env=prod app=billing-legacy owner=unknown
${WORKLOAD}-legacy-02|Standard_DS2_v2|env=test app=reporting-legacy
${WORKLOAD}-legacy-03|Standard_DS1_v2|env=prod app=batch-legacy owner=unknown
"

LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)

printf '%s\n' "$LEGACY_VMS" | while IFS='|' read -r vm size tags; do
  [ -z "$vm" ] && continue
  if az vm show --resource-group "$RESOURCE_GROUP" --name "$vm" >/dev/null 2>&1; then
    echo "Resetting $vm to retiring size $size ..."
    az vm resize --resource-group "$RESOURCE_GROUP" --name "$vm" --size "$size" --only-show-errors >/dev/null
  else
    echo "Creating legacy VM $vm ($size) ..."
    if ! az network nic show --resource-group "$RESOURCE_GROUP" --name "${vm}-nic" >/dev/null 2>&1; then
      az network nic create --resource-group "$RESOURCE_GROUP" --name "${vm}-nic" \
        --vnet-name "$VNET_NAME" --subnet "$SUBNET_NAME" --only-show-errors >/dev/null
    fi
    az vm create \
      --resource-group "$RESOURCE_GROUP" \
      --name "$vm" \
      --image Ubuntu2204 \
      --size "$size" \
      --nics "${vm}-nic" \
      --storage-sku StandardSSD_LRS \
      --admin-username "$ADMIN_USER" \
      --admin-password "$ADMIN_PASSWORD" \
      --authentication-type password \
      --tags $tags workshop=sre-agent track=vm scenario=vm-size-retirement \
      --only-show-errors --no-wait
  fi
done

# Wait for any newly created VMs to finish provisioning, then deallocate to cut cost.
printf '%s\n' "$LEGACY_VMS" | while IFS='|' read -r vm size tags; do
  [ -z "$vm" ] && continue
  az vm wait --resource-group "$RESOURCE_GROUP" --name "$vm" --created --only-show-errors >/dev/null 2>&1 || true
  az vm deallocate --resource-group "$RESOURCE_GROUP" --name "$vm" --no-wait --only-show-errors >/dev/null 2>&1 || true
done

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RETIREMENT_DATE="2027-05-31"
TRACKING_ID="0BNF-9X8"
EVENT_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat <<EOF

================================================================
Paste the following Azure Service Health advisory into the SRE Agent:
================================================================
{
  "eventSource": "ServiceHealth",
  "category": "ServiceHealth",
  "level": "Warning",
  "operationName": "Microsoft.ServiceHealth/healthadvisory/action",
  "eventTimestamp": "$EVENT_TS",
  "properties": {
    "title": "Action required: migrate off retiring Dv2/DSv2-series virtual machine sizes",
    "service": "Virtual Machines",
    "region": "$LOCATION",
    "incidentType": "ActionRequired",
    "trackingId": "$TRACKING_ID",
    "impactedService": "Virtual Machines",
    "impactedSizes": "Standard_DS1_v2 / Standard_DS2_v2 (DSv2-series)",
    "retirementDate": "$RETIREMENT_DATE",
    "subscriptionId": "$SUBSCRIPTION_ID",
    "communication": "The Dv2/DSv2-series VM sizes are being retired on $RETIREMENT_DATE. Identify all virtual machines in your control on these sizes and resize them to a current series (for example Standard_D2s_v5) before the retirement date to avoid service disruption."
  }
}
================================================================
Legacy VMs planted in $RESOURCE_GROUP: ${WORKLOAD}-legacy-01, ${WORKLOAD}-legacy-02, ${WORKLOAD}-legacy-03
EOF
```

- [ ] **Step 2: Write `inject.ps1`**

Replace `workshops/vm/scenarios/vm-size-retirement/inject.ps1` with exactly:
```powershell
#!/usr/bin/env pwsh
# Scenario — VM Size Retirement (PowerShell variant; mirrors inject.sh).
param(
    [string]$ResourceGroup = "rg-srelabvm",
    [string]$Workload = "srelabvm"
)
$ErrorActionPreference = 'Stop'

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
```

- [ ] **Step 3: Write the committed example advisory**

Create `workshops/vm/scenarios/vm-size-retirement/service-health-advisory.json` with exactly:
```json
{
  "eventSource": "ServiceHealth",
  "category": "ServiceHealth",
  "level": "Warning",
  "operationName": "Microsoft.ServiceHealth/healthadvisory/action",
  "eventTimestamp": "2026-06-22T09:00:00Z",
  "properties": {
    "title": "Action required: migrate off retiring Dv2/DSv2-series virtual machine sizes",
    "service": "Virtual Machines",
    "region": "eastus2",
    "incidentType": "ActionRequired",
    "trackingId": "0BNF-9X8",
    "impactedService": "Virtual Machines",
    "impactedSizes": "Standard_DS1_v2 / Standard_DS2_v2 (DSv2-series)",
    "retirementDate": "2027-05-31",
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "communication": "The Dv2/DSv2-series VM sizes are being retired on 2027-05-31. Identify all virtual machines in your control on these sizes and resize them to a current series (for example Standard_D2s_v5) before the retirement date to avoid service disruption."
  }
}
```

- [ ] **Step 4: Write `query.kql` (Azure Resource Graph)**

Replace `workshops/vm/scenarios/vm-size-retirement/query.kql` with exactly:
```kusto
// Azure Resource Graph query (run via the SRE Agent's Resource Graph capability
// or `az graph query -q "<this>"`). Lists every VM in the workshop resource group
// running a retiring Dv2/DSv2-series size — the "affected services under the
// agent's control". This is ARG, not Log Analytics.
Resources
| where type =~ 'microsoft.compute/virtualMachines'
| where resourceGroup =~ 'rg-srelabvm'
| extend vmSize = tostring(properties.hardwareProfile.vmSize)
| where vmSize in~ ('Standard_DS1_v2', 'Standard_DS2_v2')
| project name, vmSize, resourceGroup, location, tags
| order by name asc
```

- [ ] **Step 5: Validate the advisory JSON parses**

Run:
```bash
python3 -m json.tool workshops/vm/scenarios/vm-size-retirement/service-health-advisory.json > /dev/null && echo "advisory JSON OK"
```
Expected: `advisory JSON OK`.

- [ ] **Step 6: Lint the shell script**

Run:
```bash
bash -n workshops/vm/scenarios/vm-size-retirement/inject.sh && echo "inject.sh syntax OK"
```
Expected: `inject.sh syntax OK`.

- [ ] **Step 7: Commit**

```bash
git add workshops/vm/scenarios/vm-size-retirement/inject.sh workshops/vm/scenarios/vm-size-retirement/inject.ps1 workshops/vm/scenarios/vm-size-retirement/service-health-advisory.json workshops/vm/scenarios/vm-size-retirement/query.kql
git commit -m "feat(vm): vm-size-retirement injector, advisory payload, and ARG query"
```

---

### Task 4: Author the approval-gated migration action

**Files:**
- Create: `workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.sh`
- Create: `workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.ps1`

The script basename **must** equal the action `migrate-vm-size` (the VM approval gate resolves actions by globbing `scenarios/*/<action>.sh`). It receives `--resource-group`/`--vm-name` from the gate; `--vm-name` is ignored because the action migrates the whole affected fleet.

- [ ] **Step 1: Write `migrate-vm-size.sh`**

Create `workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.sh` with exactly:
```bash
#!/usr/bin/env bash
# Approval-gated remediation — VM Size Retirement.
# Resizes every VM in the resource group that is on a retiring size to the current
# target size. Invoked only through tools/invoke-approved-remediation.sh; the
# gate passes --vm-name, which is intentionally ignored (the whole fleet migrates).
set -euo pipefail

RESOURCE_GROUP="rg-srelabvm"
VM_NAME=""
TARGET_SIZE="Standard_D2s_v5"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -n|--vm-name) VM_NAME="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>] [--vm-name <ignored>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

FILTER="[?hardwareProfile.vmSize=='Standard_DS1_v2' || hardwareProfile.vmSize=='Standard_DS2_v2'].name"

AFFECTED=""
while IFS= read -r name; do
  [ -n "$name" ] && AFFECTED="$AFFECTED $name"
done < <(az vm list --resource-group "$RESOURCE_GROUP" --query "$FILTER" -o tsv)

if [ -z "$(printf '%s' "$AFFECTED" | tr -d '[:space:]')" ]; then
  echo "No VMs on a retiring size in $RESOURCE_GROUP. Nothing to migrate."
  exit 0
fi

COUNT=0
for vm in $AFFECTED; do
  echo "Resizing $vm -> $TARGET_SIZE ..."
  az vm resize --resource-group "$RESOURCE_GROUP" --name "$vm" --size "$TARGET_SIZE" --only-show-errors >/dev/null
  COUNT=$((COUNT + 1))
done

echo "Migration complete. Resized $COUNT VM(s) to $TARGET_SIZE."
```

- [ ] **Step 2: Write `migrate-vm-size.ps1`**

Create `workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.ps1` with exactly:
```powershell
#!/usr/bin/env pwsh
# Approval-gated remediation — VM Size Retirement (mirrors migrate-vm-size.sh).
param(
    [string]$ResourceGroup = "rg-srelabvm",
    [string]$VmName = ""
)
$ErrorActionPreference = 'Stop'

$targetSize = "Standard_D2s_v5"
$filter = "[?hardwareProfile.vmSize=='Standard_DS1_v2' || hardwareProfile.vmSize=='Standard_DS2_v2'].name"

$affected = az vm list --resource-group $ResourceGroup --query $filter -o tsv
$names = @($affected -split "`n" | Where-Object { $_.Trim().Length -gt 0 })

if ($names.Count -eq 0) {
    Write-Host "No VMs on a retiring size in $ResourceGroup. Nothing to migrate."
    exit 0
}

foreach ($name in $names) {
    Write-Host "Resizing $name -> $targetSize ..."
    az vm resize --resource-group $ResourceGroup --name $name --size $targetSize --only-show-errors | Out-Null
}

Write-Host "Migration complete. Resized $($names.Count) VM(s) to $targetSize."
```

- [ ] **Step 3: Lint the shell script**

Run:
```bash
bash -n workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.sh && echo "migrate-vm-size.sh syntax OK"
```
Expected: `migrate-vm-size.sh syntax OK`.

- [ ] **Step 4: Commit**

```bash
git add workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.sh workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.ps1
git commit -m "feat(vm): approval-gated migrate-vm-size resize action"
```

---

### Task 5: Author the validation scripts

**Files:**
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/validate.sh`
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/validate.ps1`

- [ ] **Step 1: Write `validate.sh`**

Replace `workshops/vm/scenarios/vm-size-retirement/validate.sh` with exactly:
```bash
#!/usr/bin/env bash
# Validation — VM Size Retirement. Passes (exit 0) when no VM in the resource
# group remains on a retiring size; fails (exit 1) otherwise.
set -euo pipefail

RESOURCE_GROUP="rg-srelabvm"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

FILTER="[?hardwareProfile.vmSize=='Standard_DS1_v2' || hardwareProfile.vmSize=='Standard_DS2_v2'].name"
REMAINING=$(az vm list --resource-group "$RESOURCE_GROUP" --query "$FILTER" -o tsv)

if [ -n "$(printf '%s' "$REMAINING" | tr -d '[:space:]')" ]; then
  echo "FAIL: VMs still on a retiring size:" >&2
  printf '%s\n' "$REMAINING" >&2
  exit 1
fi

echo "PASS: no VMs on a retiring size in $RESOURCE_GROUP."
```

- [ ] **Step 2: Write `validate.ps1`**

Replace `workshops/vm/scenarios/vm-size-retirement/validate.ps1` with exactly:
```powershell
#!/usr/bin/env pwsh
# Validation — VM Size Retirement (mirrors validate.sh).
param([string]$ResourceGroup = "rg-srelabvm")
$ErrorActionPreference = 'Stop'

$filter = "[?hardwareProfile.vmSize=='Standard_DS1_v2' || hardwareProfile.vmSize=='Standard_DS2_v2'].name"
$remaining = az vm list --resource-group $ResourceGroup --query $filter -o tsv

if ($remaining -and $remaining.Trim().Length -gt 0) {
    Write-Error "FAIL: VMs still on a retiring size:`n$remaining"
    exit 1
}

Write-Host "PASS: no VMs on a retiring size in $ResourceGroup."
```

- [ ] **Step 3: Lint the shell script**

Run:
```bash
bash -n workshops/vm/scenarios/vm-size-retirement/validate.sh && echo "validate.sh syntax OK"
```
Expected: `validate.sh syntax OK`.

- [ ] **Step 4: Commit**

```bash
git add workshops/vm/scenarios/vm-size-retirement/validate.sh workshops/vm/scenarios/vm-size-retirement/validate.ps1
git commit -m "feat(vm): vm-size-retirement validation (no VM on a retiring size)"
```

---

### Task 6: Author the production wiring reference (`service-health-alert.bicep`)

**Files:**
- Create: `workshops/vm/scenarios/vm-size-retirement/service-health-alert.bicep`

This is a **reference only** — not named `alert.bicep`, not wired into the aggregator, not deployed by the workshop. It must still be valid Bicep.

- [ ] **Step 1: Write the reference Bicep**

Create `workshops/vm/scenarios/vm-size-retirement/service-health-alert.bicep` with exactly:
```bicep
// ──────────────────────────────────────────────────────────────
// PRODUCTION REFERENCE — NOT deployed by the workshop.
// Shows how, in a real environment, an Azure Service Health "service retirement"
// advisory reaches the SRE Agent: a subscription-scoped Activity Log alert on
// category=ServiceHealth routes matching events to an Action Group.
//
// Azure Service Health events cannot be injected on demand, so this scenario
// SIMULATES the advisory instead (see inject.sh / service-health-advisory.json).
// This file is intentionally NOT named alert.bicep and is NOT wired into the
// scenario aggregator. Build it standalone with:
//   az bicep build --file service-health-alert.bicep --stdout
// ──────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Resource tags')
param tags object = {}

@description('Subscription scope the Service Health alert watches')
param alertScope string = subscription().id

@description('Name for the Action Group that routes Service Health events to the SRE Agent')
param actionGroupName string = 'sre-agent-servicehealth-ag'

@description('Short name (<=12 chars) shown in notifications')
param actionGroupShortName string = 'sreagent'

@description('Webhook URI the SRE Agent (or its incident intake) exposes for Service Health events')
param sreAgentWebhookUri string

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    webhookReceivers: [
      {
        name: 'sre-agent'
        serviceUri: sreAgentWebhookUri
        useCommonAlertSchema: true
      }
    ]
  }
}

resource serviceHealthRetirementAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'service-health-vm-size-retirement'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      alertScope
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'ActionRequired'
        }
        {
          field: 'properties.impactedServices[*].ServiceName'
          containsAny: [
            'Virtual Machines'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}
```

- [ ] **Step 2: Build it to verify it is valid Bicep**

Run:
```bash
az bicep build --file workshops/vm/scenarios/vm-size-retirement/service-health-alert.bicep --stdout > /dev/null && echo "reference bicep builds OK"
```
Expected: `reference bicep builds OK` (no errors; any unused-param warning would fail this gate — there should be none).

- [ ] **Step 3: Confirm CI will NOT try to wire/build it as a scenario alert**

Run:
```bash
ls workshops/vm/scenarios/vm-size-retirement/alert.bicep 2>/dev/null && echo "UNEXPECTED alert.bicep present" || echo "OK: no alert.bicep (reference is service-health-alert.bicep)"
```
Expected: `OK: no alert.bicep (reference is service-health-alert.bicep)`.

- [ ] **Step 4: Commit**

```bash
git add workshops/vm/scenarios/vm-size-retirement/service-health-alert.bicep
git commit -m "docs(vm): production Service Health alert wiring reference (not deployed)"
```

---

### Task 7: Author the attendee walkthrough (`README.md`)

**Files:**
- Modify (replace): `workshops/vm/scenarios/vm-size-retirement/README.md`

- [ ] **Step 1: Write `README.md`**

Replace `workshops/vm/scenarios/vm-size-retirement/README.md` with exactly:
````markdown
# VM Module 3: Scenario 4 — VM Size Retirement (SKU Discontinuation)

An Azure Service Health advisory announces that the **Dv2/DSv2-series** VM sizes are being retired.
The injector plants three deallocated "legacy" VMs on a retiring size so the SRE Agent can practise
the real task: **identify every affected service under its control** (via Azure Resource Graph) and
migrate it to a current size — all through the approval gate.

## How this fires in production

Azure raises VM size retirements as **Azure Service Health → Health advisories**. In a real
environment a subscription-scoped **Activity Log alert** (`category == ServiceHealth`) routes the
advisory through an **Action Group** to the SRE Agent's incident intake. That production wiring is
shown for reference in [`service-health-alert.bicep`](./service-health-alert.bicep) (an Action
Group + an `activityLogAlerts` resource).

> **Service Health events can't be injected on demand**, so this scenario *simulates* the kickoff:
> `inject` prints a realistic Service Health advisory payload — the same shape Azure would send —
> for you to paste into the agent. Everything after the kickoff (the Resource Graph inventory and
> the approval-gated migration) runs against real resources.

## Inject fault

```bash
./inject.sh --resource-group rg-srelabvm
# PowerShell: pwsh ./inject.ps1 -ResourceGroup rg-srelabvm
```

This creates `srelabvm-legacy-01/02/03` (deallocated, on `Standard_DS1_v2`/`Standard_DS2_v2`) and
prints the Service Health advisory to paste into the agent.

## Kick off the agent

Paste the advisory JSON that `inject` emitted (a committed example is in
[`service-health-advisory.json`](./service-health-advisory.json)) into the SRE Agent and ask it to
identify all affected VMs and prepare the migration.

## Investigation flow

The agent enumerates affected VMs with an Azure Resource Graph query ([`query.kql`](./query.kql)):

```bash
az graph query -q "Resources | where type =~ 'microsoft.compute/virtualMachines' | where resourceGroup =~ 'rg-srelabvm' | extend vmSize = tostring(properties.hardwareProfile.vmSize) | where vmSize in~ ('Standard_DS1_v2','Standard_DS2_v2') | project name, vmSize, tags"
```

Expected: the three `srelabvm-legacy-*` VMs. The `Standard_B2s` baseline VMs
(`srelabvm-vm01`/`srelabvm-vm02`) are not affected.

## Remediate (approval required)

Migration is disruptive (a resize), so it runs only through the approval gate with a CHG/INC ticket:

```powershell
..\..\tools\Invoke-ApprovedRemediation.ps1 -Action migrate-vm-size -ResourceGroup rg-srelabvm -VmName srelabvm-vm01 -ChangeTicket CHG-12345
```
```bash
../../tools/invoke-approved-remediation.sh --action migrate-vm-size --change-ticket CHG-12345
```

The `migrate-vm-size` action discovers every VM on a retiring size and resizes it to
`Standard_D2s_v5`, writing an audit entry. (The `-VmName` argument is required by the gate, but the
action migrates the whole affected fleet, not a single VM.)

## Validate

```bash
./validate.sh --resource-group rg-srelabvm
```

Passes when no VM in the resource group remains on a retiring size.

## Next step

See [90. Watch Agent Workflow](../../docs/90-watch-agent-workflow.md).
````

- [ ] **Step 2: Commit**

```bash
git add workshops/vm/scenarios/vm-size-retirement/README.md
git commit -m "docs(vm): vm-size-retirement attendee walkthrough"
```

---

### Task 8: Add the action to the VM incident-response doc

**Files:**
- Modify: `workshops/vm/docs/02-configure-incident-response.md` (the "Available actions" table)

- [ ] **Step 1: Add the table row**

In `workshops/vm/docs/02-configure-incident-response.md`, find the actions table row:
```markdown
| `stop-cpu-runaway` | Stops the sustained CPU workload | Scenario 3 remediation |
```
and add a new row immediately after it:
```markdown
| `migrate-vm-size` | Resizes every VM on a retiring size to the current target (`Standard_D2s_v5`) | Scenario 4 (VM size retirement) migration |
```

- [ ] **Step 2: Commit**

```bash
git add workshops/vm/docs/02-configure-incident-response.md
git commit -m "docs(vm): list migrate-vm-size in the approval-gate actions table"
```

---

### Task 9: Make scripts executable, regenerate artifacts, and validate

**Files:**
- Modify (regenerated): `workshops/vm/scenarios/INDEX.md`, `workshops/vm/README.md`
- Mode change: all `.sh` files in the scenario folder

- [ ] **Step 1: Make the shell scripts executable**

Run:
```bash
chmod +x workshops/vm/scenarios/vm-size-retirement/*.sh
git update-index --chmod=+x \
  workshops/vm/scenarios/vm-size-retirement/inject.sh \
  workshops/vm/scenarios/vm-size-retirement/validate.sh \
  workshops/vm/scenarios/vm-size-retirement/migrate-vm-size.sh 2>/dev/null || true
ls -l workshops/vm/scenarios/vm-size-retirement/*.sh
```
Expected: `inject.sh`, `validate.sh`, `migrate-vm-size.sh` all show the executable bit (`-rwxr-xr-x`).

- [ ] **Step 2: Regenerate the generated artifacts**

Run:
```bash
scripts/validate-scenarios.sh --write
```
Expected: completes without error; `git status` shows modifications to `workshops/vm/scenarios/INDEX.md` and `workshops/vm/README.md` (the scenario table now includes a `VM Size Retirement (SKU Discontinuation)` row).

- [ ] **Step 3: Confirm the aggregator did NOT change (alert-less scenario causes no drift)**

Run:
```bash
git status --porcelain workshops/vm/infra/bicep/modules/scenario-alerts.bicep
```
Expected: **empty output** (the aggregator is unchanged because this scenario has no `signal`).

- [ ] **Step 4: Run the drift/schema validation**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: prints `Scenario validation passed`.

- [ ] **Step 5: Run the scenario-tools unit tests**

Run:
```bash
cd scripts/scenario-tools && npm test; cd - >/dev/null
```
Expected: all tests pass (exit 0).

- [ ] **Step 6: Build the VM track main Bicep (exercises the unchanged aggregator)**

Run:
```bash
az bicep build --file workshops/vm/infra/bicep/main.bicep --stdout > /dev/null && echo "main.bicep builds OK"
```
Expected: `main.bicep builds OK`.

- [ ] **Step 7: Commit the regenerated artifacts**

```bash
git add workshops/vm/scenarios/INDEX.md workshops/vm/README.md workshops/vm/scenarios/vm-size-retirement
git commit -m "feat(vm): register vm-size-retirement (regenerate INDEX + README table)"
```

---

### Task 10: Final end-to-end verification

- [ ] **Step 1: Confirm the full file set is present and correct**

Run:
```bash
ls workshops/vm/scenarios/vm-size-retirement
```
Expected exactly: `README.md inject.ps1 inject.sh migrate-vm-size.ps1 migrate-vm-size.sh query.kql scenario.yaml service-health-advisory.json service-health-alert.bicep validate.ps1 validate.sh` (NO `alert.bicep`, NO `remediate.*`).

- [ ] **Step 2: Re-run the validators clean**

Run:
```bash
scripts/validate-scenarios.sh && cd scripts/scenario-tools && npm test; cd - >/dev/null
```
Expected: `Scenario validation passed` and all unit tests pass.

- [ ] **Step 3: Confirm no uncommitted changes remain**

Run:
```bash
git status --porcelain
```
Expected: empty (everything committed).

---

## Self-review notes (verified while writing)

- **Spec coverage:** every spec section maps to a task — manifest (T2), inject + advisory + ARG query (T3), approval-gated migration (T4), validation (T5), production reference (T6), README notice (T7), docs touch-up (T8), regeneration/no-drift/tests (T9), final verification (T10).
- **No wired alert:** `alert.bicep` deleted (T1); `signal` omitted (T2); aggregator no-drift asserted (T9 Step 3). The reference is `service-health-alert.bicep`, not `alert.bicep`, so CI's `alert.bicep`-globbed build skips it (T6 Step 3).
- **Action naming:** `migrate-vm-size` is the action and the script basename (T4) — satisfies the VM approval-gate glob and is unique in the track.
- **Retiring/target sizes** are identical across `inject`, `query.kql`, `migrate-vm-size`, and `validate` (`Standard_DS1_v2`/`Standard_DS2_v2` → `Standard_D2s_v5`).
- **Runtime caveat:** creating/resizing live VMs is validated manually per the workshop flow; CI only runs schema/drift/tests/bicep-build. If `Standard_D2s_v5` is unavailable in a chosen region at run time, fall back to `Standard_D2as_v5` (update `TARGET_SIZE` in both `migrate-vm-size` scripts).

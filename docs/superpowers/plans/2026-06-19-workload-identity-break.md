# Workload Identity Break — AKS Scenario Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second AKS scenario, `workload-identity-break`, that injects an *authentication* fault (deleting the workload's federated identity credential) so pods can no longer exchange their ServiceAccount token for an Azure AD token — contrasting with the existing *authorization* fault in `cosmos-rbac-removal`.

**Architecture:** The scenario is a self-contained folder under `workshops/aks/scenarios/workload-identity-break/` that conforms to the repo's scenario framework (`schemas/scenario.schema.json`). It is scaffolded with `scripts/new-scenario.sh`, its eight files are filled with real content, and the shared/generated artifacts (`scenario-alerts.bicep`, `INDEX.md`, the AKS `README.md` table) are regenerated with `scripts/validate-scenarios.sh --write`. No `identity.bicep` or other live infra is changed — the `federatedCredential` block already models desired state; the README narrative has the attendee remove it and `@copilot` restore it during the workshop run.

**Tech Stack:** Bash + PowerShell tool scripts, Azure CLI (`az`), `kubectl`, Bicep (`Microsoft.Insights/scheduledQueryRules`), KQL, Node.js scenario-tools (validator/generator), YAML manifest.

---

## Before You Start

- This is **new feature work** that lands via PR so the `validate-scenarios.yml` CI gate runs. Create an isolated branch/worktree first (the executing skill / `superpowers:using-git-worktrees` handles this). Suggested branch: `feat/scenario-workload-identity-break`.
- **No live Azure changes** are made while building this scenario. The only "tests" are the framework validators and `az bicep build` (offline compile). Runtime fault injection is validated manually per the workshop flow, outside CI.
- Source of truth: the approved spec at `docs/superpowers/specs/2026-06-19-workload-identity-break-scenario-design.md`.

## How "tests" work for this plan

There is **no per-scenario unit-test harness**. The acceptance gates are:

- `scripts/validate-scenarios.sh` → must print `Scenario validation passed` (schema + cross-field + drift checks).
- `cd scripts/scenario-tools && npm test` → 13/13 still pass (framework logic; unaffected by adding a live scenario, run as a regression check).
- `az bicep build --file workshops/aks/scenarios/workload-identity-break/alert.bicep --stdout` → compiles.
- `az bicep build --file workshops/aks/infra/bicep/main.bicep --stdout` → compiles (exercises the regenerated aggregator + the new `alert.bicep`).

The validator only checks **structure** (files exist, `.sh` executable, ids/tracks match, action names unique, no generated-artifact drift) — it does **not** semantically execute the scripts/queries. So the scenario folder stays "valid" throughout as long as all files exist; we fill real content task-by-task and re-run the validator after each change as the regression gate.

## File Structure

All new files live in `workshops/aks/scenarios/workload-identity-break/`:

| File | Responsibility |
| --- | --- |
| `scenario.yaml` | Manifest: id/title/track/summary/severity/objectives + inject/validate/remediate script pairs + signal/investigation/docPage. |
| `inject.sh` / `inject.ps1` | Break: delete the live federated identity credential + restart pods. |
| `remediate.sh` / `remediate.ps1` | Manual-fallback fix: recreate the federated credential (discover OIDC issuer) + restart pods. |
| `validate.sh` / `validate.ps1` | Health probe: `curl /items`, exit 0 on HTTP 200. |
| `alert.bicep` | Detection: scheduled-query-rule keyed on AAD token-exchange errors, scoped to the AKS cluster. |
| `query.kql` | Investigation query mirroring the alert's authn filter. |
| `README.md` | Attendee walkthrough (docPage), authn-vs-authz framing, code-restoration remediation. |

Regenerated (never hand-edited) shared artifacts that gain a row/module:

- `workshops/aks/infra/bicep/modules/scenario-alerts.bicep`
- `workshops/aks/scenarios/INDEX.md`
- `workshops/aks/README.md` (between `<!-- BEGIN SCENARIOS -->` / `<!-- END SCENARIOS -->`)

---

## Task 1: Scaffold the scenario and wire its manifest

**Files:**
- Create (via scaffolder): `workshops/aks/scenarios/workload-identity-break/{scenario.yaml,inject.sh,inject.ps1,remediate.sh,remediate.ps1,validate.sh,validate.ps1,alert.bicep,query.kql,README.md}`
- Replace: `workshops/aks/scenarios/workload-identity-break/scenario.yaml`
- Regenerate: `workshops/aks/infra/bicep/modules/scenario-alerts.bicep`, `workshops/aks/scenarios/INDEX.md`, `workshops/aks/README.md`

- [ ] **Step 1: Run the scaffolder**

Run:
```bash
scripts/new-scenario.sh aks workload-identity-break "Workload Identity Break"
```
Expected: it prints the created files and exits 0. The new folder `workshops/aks/scenarios/workload-identity-break/` now contains token-substituted template stubs.

- [ ] **Step 2: Verify the files were created**

Run:
```bash
ls -l workshops/aks/scenarios/workload-identity-break/
```
Expected: the 10 files listed above are present, and `inject.sh`, `remediate.sh`, `validate.sh` show the executable bit (`-rwxr-xr-x`).

- [ ] **Step 3: Ensure the `.sh` scripts are executable**

Run:
```bash
chmod +x workshops/aks/scenarios/workload-identity-break/*.sh
```
Expected: no output (idempotent — the validator requires `.sh` files to be executable).

- [ ] **Step 4: Replace `scenario.yaml` with the final manifest**

Overwrite `workshops/aks/scenarios/workload-identity-break/scenario.yaml` with exactly:
```yaml
id: workload-identity-break
title: Workload Identity Break
track: aks
summary: The workload's federated identity credential is deleted, so pods cannot acquire an AAD token and /items returns HTTP 500 with auth errors while /health stays green.
severity: 3
estimatedMinutes: 30
difficulty: advanced
learningObjectives:
  - Distinguish authentication (token acquisition) failures from authorization (RBAC) failures.
  - Trace AADSTS70021 / "No matching federated identity" errors in ContainerLog to a missing federated identity credential.
  - Reconcile a missing federated identity credential by restoring the federatedCredential block in identity.bicep via a GitHub issue / @copilot PR (GitOps), with a manual fallback.
signal:
  alertModule: alert.bicep
  alertName: workload-identity-auth-errors
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: restore-federated-credential
    bash: remediate.sh
    powershell: remediate.ps1
    description: Recreate the federated identity credential binding the workshop-app ServiceAccount to the UAMI, and restart pods.
investigation:
  query: query.kql
docPage: README.md
```

- [ ] **Step 5: Regenerate the shared artifacts**

Run:
```bash
scripts/validate-scenarios.sh --write
```
Expected: prints `Scenario validation passed`. This regenerates `scenario-alerts.bicep`, `INDEX.md`, and the AKS `README.md` table to include the new scenario.

- [ ] **Step 6: Confirm the aggregator gained the new module**

Run:
```bash
git --no-pager diff workshops/aks/infra/bicep/modules/scenario-alerts.bicep
```
Expected: a new module block is added (scenarios sort by id, so it appears after `cosmosRbacRemovalAlert`):
```bicep
module workloadIdentityBreakAlert '../../../scenarios/workload-identity-break/alert.bicep' = {
  name: 'alert-workload-identity-break'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    scopeResourceId: clusterId
  }
}
```
Also confirm `workshops/aks/scenarios/INDEX.md` and `workshops/aks/README.md` each gained a `Workload Identity Break` row.

- [ ] **Step 7: Re-run validation without `--write` to confirm no drift**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed` (the committed artifacts match the freshly generated ones).

- [ ] **Step 8: Commit**

```bash
git add workshops/aks/scenarios/workload-identity-break/ \
        workshops/aks/infra/bicep/modules/scenario-alerts.bicep \
        workshops/aks/scenarios/INDEX.md \
        workshops/aks/README.md
git commit -m "feat(aks): scaffold workload-identity-break scenario and wire manifest

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 2: Implement the inject (break) scripts

**Files:**
- Modify: `workshops/aks/scenarios/workload-identity-break/inject.sh`
- Modify: `workshops/aks/scenarios/workload-identity-break/inject.ps1`

- [ ] **Step 1: Write `inject.sh`**

Overwrite `workshops/aks/scenarios/workload-identity-break/inject.sh` with exactly:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Break: delete the workload's federated identity credential so pods can no
# longer exchange their ServiceAccount token for an Azure AD token.
RESOURCE_GROUP="rg-srelab"
WORKLOAD="srelab"
NAMESPACE="workshop"
DEPLOYMENT="web-app"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -w|--workload) WORKLOAD="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [-g|--resource-group <rg>] [-w|--workload <name>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

FED_CRED="${WORKLOAD}-fed-cred"
IDENTITY="${WORKLOAD}-id"

EXISTING=$(az identity federated-credential list \
  --identity-name "$IDENTITY" --resource-group "$RESOURCE_GROUP" \
  --query "[?name=='${FED_CRED}'].name" -o tsv 2>/dev/null || true)

if [ -z "$EXISTING" ]; then
  echo "No federated credential '${FED_CRED}' to delete (already broken?)"
else
  az identity federated-credential delete \
    --name "$FED_CRED" --identity-name "$IDENTITY" --resource-group "$RESOURCE_GROUP" --yes
  echo "Deleted federated credential ${FED_CRED} on ${IDENTITY}"
fi

kubectl rollout restart "deployment/$DEPLOYMENT" -n "$NAMESPACE"
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s
echo "Fault injected: workload identity federated credential removed and pods restarted."
```

- [ ] **Step 2: Write `inject.ps1`**

Overwrite `workshops/aks/scenarios/workload-identity-break/inject.ps1` with exactly:
```powershell
#!/usr/bin/env pwsh
param([string]$ResourceGroup = "rg-srelab", [string]$Workload = "srelab", [string]$Namespace = "workshop", [string]$Deployment = "web-app")
$ErrorActionPreference = 'Stop'
$fedCred = "$Workload-fed-cred"
$identity = "$Workload-id"
$existing = az identity federated-credential list --identity-name $identity --resource-group $ResourceGroup --query "[?name=='$fedCred'].name" -o tsv
if ($existing) {
    az identity federated-credential delete --name $fedCred --identity-name $identity --resource-group $ResourceGroup --yes
    Write-Host "Deleted federated credential $fedCred on $identity"
} else { Write-Host "No federated credential '$fedCred' to delete (already broken?)" }
kubectl rollout restart "deployment/$Deployment" -n $Namespace
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=90s
Write-Host "Fault injected: workload identity federated credential removed and pods restarted."
```

- [ ] **Step 3: Keep `inject.sh` executable**

Run:
```bash
chmod +x workshops/aks/scenarios/workload-identity-break/inject.sh
```
Expected: no output.

- [ ] **Step 4: Validate (regression gate)**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 5: Commit**

```bash
git add workshops/aks/scenarios/workload-identity-break/inject.sh \
        workshops/aks/scenarios/workload-identity-break/inject.ps1
git commit -m "feat(aks): implement workload-identity-break inject scripts

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 3: Implement the remediate (manual-fallback fix) scripts

**Files:**
- Modify: `workshops/aks/scenarios/workload-identity-break/remediate.sh`
- Modify: `workshops/aks/scenarios/workload-identity-break/remediate.ps1`

- [ ] **Step 1: Write `remediate.sh`**

Overwrite `workshops/aks/scenarios/workload-identity-break/remediate.sh` with exactly:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Manual fallback fix: recreate the federated identity credential that binds the
# workshop-app ServiceAccount to the UAMI via the AKS OIDC issuer, then restart
# pods. The primary remediation in the workshop is the @copilot PR restoring the
# federatedCredential block in identity.bicep + a Deploy AKS Infrastructure run.
RESOURCE_GROUP="rg-srelab"
WORKLOAD="srelab"
NAMESPACE="workshop"
DEPLOYMENT="web-app"
SA_SUBJECT="system:serviceaccount:workshop:workshop-app"
AUDIENCE="api://AzureADTokenExchange"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -w|--workload) WORKLOAD="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [-g|--resource-group <rg>] [-w|--workload <name>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

FED_CRED="${WORKLOAD}-fed-cred"
IDENTITY="${WORKLOAD}-id"

CLUSTER=$(az aks list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$CLUSTER" ]; then echo "No AKS cluster found in $RESOURCE_GROUP" >&2; exit 1; fi

OIDC_ISSUER=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER" \
  --query oidcIssuerProfile.issuerUrl -o tsv)
if [ -z "$OIDC_ISSUER" ]; then echo "Could not resolve OIDC issuer for $CLUSTER" >&2; exit 1; fi

az identity federated-credential create \
  --name "$FED_CRED" --identity-name "$IDENTITY" --resource-group "$RESOURCE_GROUP" \
  --issuer "$OIDC_ISSUER" \
  --subject "$SA_SUBJECT" \
  --audiences "$AUDIENCE"
echo "Recreated federated credential ${FED_CRED} on ${IDENTITY} (issuer ${OIDC_ISSUER})"

kubectl rollout restart "deployment/$DEPLOYMENT" -n "$NAMESPACE"
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s
echo "Remediation complete: federated credential restored and pods restarted."
```

- [ ] **Step 2: Write `remediate.ps1`**

Overwrite `workshops/aks/scenarios/workload-identity-break/remediate.ps1` with exactly:
```powershell
#!/usr/bin/env pwsh
param([string]$ResourceGroup = "rg-srelab", [string]$Workload = "srelab", [string]$Namespace = "workshop", [string]$Deployment = "web-app")
$ErrorActionPreference = 'Stop'
$fedCred = "$Workload-fed-cred"
$identity = "$Workload-id"
$subject = "system:serviceaccount:workshop:workshop-app"
$audience = "api://AzureADTokenExchange"
$cluster = az aks list --resource-group $ResourceGroup --query "[0].name" -o tsv
if (-not $cluster) { throw "No AKS cluster found in $ResourceGroup" }
$oidcIssuer = az aks show --resource-group $ResourceGroup --name $cluster --query oidcIssuerProfile.issuerUrl -o tsv
if (-not $oidcIssuer) { throw "Could not resolve OIDC issuer for $cluster" }
az identity federated-credential create --name $fedCred --identity-name $identity --resource-group $ResourceGroup --issuer $oidcIssuer --subject $subject --audiences $audience
Write-Host "Recreated federated credential $fedCred on $identity (issuer $oidcIssuer)"
kubectl rollout restart "deployment/$Deployment" -n $Namespace
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=90s
Write-Host "Remediation complete: federated credential restored and pods restarted."
```

- [ ] **Step 3: Keep `remediate.sh` executable**

Run:
```bash
chmod +x workshops/aks/scenarios/workload-identity-break/remediate.sh
```
Expected: no output.

- [ ] **Step 4: Validate (regression gate)**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 5: Commit**

```bash
git add workshops/aks/scenarios/workload-identity-break/remediate.sh \
        workshops/aks/scenarios/workload-identity-break/remediate.ps1
git commit -m "feat(aks): implement workload-identity-break remediate scripts

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 4: Implement the validate (health-probe) scripts

**Files:**
- Modify: `workshops/aks/scenarios/workload-identity-break/validate.sh`
- Modify: `workshops/aks/scenarios/workload-identity-break/validate.ps1`

- [ ] **Step 1: Write `validate.sh`**

Overwrite `workshops/aks/scenarios/workload-identity-break/validate.sh` with exactly:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Health probe: the app's /items endpoint should return HTTP 200 when the
# workload identity is intact. Exit 0 on 200, non-zero otherwise.
NAMESPACE="workshop"
SERVICE="web-app"

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--service) SERVICE="$2"; shift 2 ;;
    -N|--namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [-s|--service <svc>] [-N|--namespace <ns>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

APP_IP=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$APP_IP" ]; then echo "No external IP yet for svc/$SERVICE" >&2; exit 1; fi

CODE=$(curl -fsS -o /dev/null -w '%{http_code}' "http://$APP_IP/items" || true)
echo "GET http://$APP_IP/items -> $CODE"
if [ "$CODE" = "200" ]; then echo "Healthy: /items returns 200"; exit 0; fi
echo "Degraded: /items did not return 200" >&2
exit 1
```

- [ ] **Step 2: Write `validate.ps1`**

Overwrite `workshops/aks/scenarios/workload-identity-break/validate.ps1` with exactly:
```powershell
#!/usr/bin/env pwsh
param([string]$Service = "web-app", [string]$Namespace = "workshop")
$ErrorActionPreference = 'Stop'
$ip = kubectl get svc $Service -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
if (-not $ip) { throw "No external IP yet for svc/$Service" }
try { $resp = Invoke-WebRequest -Uri "http://$ip/items" -UseBasicParsing; $code = $resp.StatusCode }
catch { $code = $_.Exception.Response.StatusCode.value__ }
Write-Host "GET http://$ip/items -> $code"
if ($code -eq 200) { Write-Host "Healthy: /items returns 200"; exit 0 }
Write-Error "Degraded: /items did not return 200"; exit 1
```

- [ ] **Step 3: Keep `validate.sh` executable**

Run:
```bash
chmod +x workshops/aks/scenarios/workload-identity-break/validate.sh
```
Expected: no output.

- [ ] **Step 4: Validate (regression gate)**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 5: Commit**

```bash
git add workshops/aks/scenarios/workload-identity-break/validate.sh \
        workshops/aks/scenarios/workload-identity-break/validate.ps1
git commit -m "feat(aks): implement workload-identity-break validate scripts

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 5: Author the alert and investigation query

**Files:**
- Modify: `workshops/aks/scenarios/workload-identity-break/alert.bicep`
- Modify: `workshops/aks/scenarios/workload-identity-break/query.kql`

**Contract reminder:** `alert.bicep` must declare **exactly** the params `location`, `workloadName`, `tags`, `scopeResourceId` (the generated aggregator passes these), and bind `scopes: [scopeResourceId]`.

- [ ] **Step 1: Write `alert.bicep`**

Overwrite `workshops/aks/scenarios/workload-identity-break/alert.bicep` with exactly:
```bicep
@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (AKS cluster)')
param scopeResourceId string

resource authErrorsAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-workload-identity-auth-errors'
  location: location
  tags: tags
  properties: {
    displayName: 'Workload Identity Auth Errors'
    description: 'Fires when the workshop app logs Azure AD token-exchange failures in container logs — typically a missing or misconfigured federated identity credential (authentication failure).'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      scopeResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            let workshopContainers = KubePodInventory
            | where Namespace == "workshop"
            | where TimeGenerated > ago(1h)
            | distinct ContainerID;
            ContainerLog
            | where ContainerID in (workshopContainers)
            | where LogEntry has "AADSTS70021" or LogEntry has "No matching federated identity" or LogEntry has "ManagedIdentityCredential" or LogEntry has "AADSTS"
            | summarize ErrorCount = count() by bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}
```

- [ ] **Step 2: Write `query.kql`**

Overwrite `workshops/aks/scenarios/workload-identity-break/query.kql` with exactly:
```kql
// Workload Identity Break — investigation query.
// Surfaces Azure AD token-exchange failures from the workshop app's containers,
// pointing at a missing/misconfigured federated identity credential.
let workshopContainers = KubePodInventory
| where Namespace == "workshop"
| where TimeGenerated > ago(1h)
| distinct ContainerID;
ContainerLog
| where ContainerID in (workshopContainers)
| where LogEntry has "AADSTS70021" or LogEntry has "No matching federated identity" or LogEntry has "ManagedIdentityCredential" or LogEntry has "AADSTS"
| project TimeGenerated, LogEntry
| top 50 by TimeGenerated desc
```

- [ ] **Step 3: Compile the alert module on its own**

Run:
```bash
az bicep build --file workshops/aks/scenarios/workload-identity-break/alert.bicep --stdout > /dev/null && echo "alert.bicep OK"
```
Expected: `alert.bicep OK` (no Bicep errors/warnings printed before it).

- [ ] **Step 4: Confirm no generated-artifact drift and validate**

Run:
```bash
scripts/validate-scenarios.sh --write && git --no-pager diff --stat
```
Expected: `Scenario validation passed`, and **no** changes to `scenario-alerts.bicep` / `INDEX.md` / `README.md` (the alert content change does not alter the generated wiring — the aggregator references `alert.bicep` by path). Then run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 5: Commit**

```bash
git add workshops/aks/scenarios/workload-identity-break/alert.bicep \
        workshops/aks/scenarios/workload-identity-break/query.kql
git commit -m "feat(aks): add workload-identity-break alert and investigation query

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 6: Write the attendee walkthrough (`README.md`)

**Files:**
- Modify: `workshops/aks/scenarios/workload-identity-break/README.md`

- [ ] **Step 1: Write `README.md`**

Overwrite `workshops/aks/scenarios/workload-identity-break/README.md` with exactly:
````markdown
# Break It: Workload Identity 💥 (~30 min)

## Overview

This scenario introduces an **authentication** fault — a different failure class from `cosmos-rbac-removal` (which is an *authorization* fault). You'll remove the **federated identity credential** that lets your pods exchange their Kubernetes ServiceAccount token for an Azure AD token. Without it, the app can't authenticate to Azure at all: every `/items` request returns HTTP 500 with an `AADSTS70021: No matching federated identity record found` error, while `/health` keeps returning 200.

> **Authn vs authz:** In `cosmos-rbac-removal` the identity was valid but lacked a *role* (authorization). Here the identity can't even obtain a *token* (authentication) — the failure happens one step earlier in the chain.

## The Scenario

> _During an identity hygiene review, an engineer is auditing user-assigned managed identities. They find a federated identity credential on `srelab-id` with an unfamiliar issuer URL and a subject referencing a Kubernetes ServiceAccount. It looks like leftover federation from an old migration. They remove the `federatedCredential` block from the Bicep, commit, and the PR merges cleanly — the template is valid. The next infrastructure deploy reconciles it away._
>
> _Pods are running. Health checks are green. But every data request now fails with a cryptic `AADSTS70021` error. The app can no longer prove who it is to Azure._

This is the scenario you're about to create — and then watch your SRE Agent detect, diagnose, and fix it.

## Verify Current State

Before you break anything, confirm the app is working:

```bash
# Set the IP again (if not already set)
export APP_IP=$(kubectl get svc web-app -n workshop -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# This should return 200
curl http://$APP_IP/items

# Expected output: [] or a list of items
```

Good? Let's break it.

## Make the Change

1. **Open** `workshops/aks/infra/bicep/modules/identity.bicep` in your editor
2. **Find the federated identity credential** — look for this comment block:
   ```bicep
   // ──────────────────────────────────────────────
   // Federated Identity Credential
   // Links K8s ServiceAccount → UAMI via AKS OIDC issuer
   // ──────────────────────────────────────────────
   ```
3. **Below it you'll see the resource definition:**
   ```bicep
   resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
     parent: uami
     name: '${workloadName}-fed-cred'
     properties: {
       issuer: aksOidcIssuerUrl
       subject: 'system:serviceaccount:${k8sNamespace}:${k8sServiceAccountName}'
       audiences: [
         'api://AzureADTokenExchange'
       ]
     }
   }
   ```
4. **Delete or comment out the entire `federatedCredential` resource block** — from `resource federatedCredential` through its closing `}`
5. **Save the file**

The UAMI and its CosmosDB role assignment still exist — but pods can no longer obtain a token *as* that UAMI, because the trust between the Kubernetes ServiceAccount and the identity is gone.

## Deploy the Fault

```bash
# Stage the change
git add workshops/aks/infra/bicep/modules/identity.bicep

# Commit with a realistic message
git commit -m "identity cleanup: remove stale federated credential"

# Push to main (or merge if you used a branch)
git push origin main
```

When you push, the `Validate AKS Infrastructure` workflow runs automatically — it checks Bicep syntax and shows a what-if preview, but it doesn't deploy anything. To actually deploy the broken infrastructure:

1. **Go to GitHub** → your fork → **Actions** tab
2. **Select "Deploy AKS Infrastructure"** in the left sidebar
3. **Click "Run workflow"** → choose your region and workload name → **Run workflow**
4. **Watch it complete** (~3–5 minutes)

The deployment will **succeed**. The Bicep template is valid syntactically.

> **⚠️ Important:** Azure Resource Manager uses **incremental deployment mode** by default, so removing the federated credential from the Bicep template does **not** automatically delete it in Azure — it only stops managing it. To actually trigger the fault, delete the live credential after the deployment completes:

```bash
az identity federated-credential delete \
  --name srelab-fed-cred \
  --identity-name srelab-id \
  --resource-group rg-srelab \
  --yes
```

> **Why two steps?** This mirrors a real identity-cleanup-gone-wrong: the Bicep change removes the credential from the "desired state" (your code), and the CLI deletion simulates Azure catching up. When the SRE Agent investigates, it finds the credential missing from both the Bicep code *and* the live environment.

After deleting the credential, **restart the pods** so they attempt a fresh (now-failing) token exchange:

```bash
kubectl rollout restart deployment/web-app -n workshop
kubectl rollout status deployment/web-app -n workshop --timeout=90s
```

## Watch It Break

The pods are running, but the app can no longer authenticate to Azure. Try this:

```bash
# Health check still passes (it doesn't authenticate to Azure)
curl http://$APP_IP/health

# Returns 200: {"status":"healthy","timestamp":"..."}
# Everything looks fine!
```

But now:

```bash
# The items endpoint fails
curl http://$APP_IP/items

# Returns 500 with an error message like:
# {
#   "error": "Failed to connect to CosmosDB: ... AADSTS70021: No matching federated identity record found for presented assertion ..."
# }
```

**The app is broken.** Health checks are passing. Pods are running. But the app can't authenticate to Azure, so every data request fails *before* it ever reaches CosmosDB's authorization check.

## What's Happening Under the Hood

Here's the sequence of events:

```
1. Bicep deployment removes federatedCredential from managed state
   ↓
2. CLI command deletes the actual federated credential from the UAMI
   ↓
3. Pod restart clears any cached AAD tokens
   ↓
4. App tries to authenticate: it presents its projected ServiceAccount
   (OIDC) token to Azure AD to exchange for a UAMI token
   ↓
5. Azure AD looks for a federated identity credential matching
   (issuer, subject) — and finds none
   ↓
6. Azure AD rejects the exchange: AADSTS70021
   "No matching federated identity record found"
   ↓
7. The app never gets a token — the CosmosDB call fails at the
   AUTHENTICATION step (before any RBAC/authorization check)
   ↓
8. App catches the error and returns 500 to the client
   ↓
9. Azure Monitor detects the AADSTS / token-exchange errors in container logs
   ↓
10. The "Workload Identity Auth Errors" alert fires → SRE Agent is triggered
```

> **Contrast with `cosmos-rbac-removal`:** there, the token exchange *succeeded* and CosmosDB rejected the request with a 403 (authorization). Here, the token exchange itself *fails* (authentication). The distinct alert keys (`AADSTS70021`, `No matching federated identity`) let the agent tell the two apart.

## What Happens Next

Your Azure Monitor alert detects the authentication errors. The SRE Agent, which you configured during onboarding, will:

1. **Receive the alert** from Azure Monitor
2. **Query the logs** and find the `AADSTS70021` / token-exchange errors
3. **Check pod logs** to confirm the authentication failures
4. **Correlate with recent deployments** (find the `identity.bicep` change you just made)
5. **Read the Bicep code** to understand what changed
6. **Identify the root cause:** the missing `federatedCredential`
7. **Propose a fix** — restore the `federatedCredential` block — and open a PR on your fork
8. **If you configured it for Autonomous mode,** the agent merges the PR; you then trigger the `Deploy AKS Infrastructure` workflow to apply the fix

You don't need to fix this yourself. **Don't troubleshoot.** Don't manually recreate the credential. Let the SRE Agent do its job.

## Optional: Add More Narrative

If you're running this workshop with a group, this is a great moment for storytelling:

- **"Notice how the health checks still pass?"** — Liveness probes don't authenticate to Azure, so they stay green while the real business flow is dead.
- **"This is authentication, not authorization."** — The identity is fine; it just can't prove who it is. That's a different signature than a 403 RBAC denial.
- **"The Bicep change was valid. No syntax errors. The deploy succeeded."** — Infrastructure-as-code catches syntax, not intent. You need observability and automation to catch these.

## Next Step

→ **[Watch the SRE Agent Work](../../docs/90-watch-sre-agent.md)**

In the next module, you'll navigate to the SRE Agent portal and observe its full investigation and remediation flow — correlating logs, reading your code, and opening a PR that restores the federated credential.
````

- [ ] **Step 2: Validate (regression gate)**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 3: Commit**

```bash
git add workshops/aks/scenarios/workload-identity-break/README.md
git commit -m "docs(aks): add workload-identity-break attendee walkthrough

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 7: Full acceptance gate

**Files:** none modified — this task runs the full validation suite and (optionally) opens the PR.

- [ ] **Step 1: Run the scenario validator (drift + structure)**

Run:
```bash
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 2: Run the framework unit tests**

Run:
```bash
cd scripts/scenario-tools && npm test; cd - >/dev/null
```
Expected: all tests pass (13/13), exit 0.

- [ ] **Step 3: Compile the full AKS Bicep (exercises the regenerated aggregator + new alert)**

Run:
```bash
az bicep build --file workshops/aks/infra/bicep/main.bicep --stdout > /dev/null && echo "main.bicep OK"
```
Expected: `main.bicep OK`.

- [ ] **Step 4: Confirm a clean tree and full regeneration are in sync**

Run:
```bash
scripts/validate-scenarios.sh --write && git status --porcelain
```
Expected: `Scenario validation passed` and **no** output from `git status --porcelain` (everything already committed; regeneration produced no drift).

- [ ] **Step 5: Push the branch and open the PR**

```bash
git push -u origin feat/scenario-workload-identity-break
gh pr create --fill --title "feat(aks): add workload-identity-break scenario"
```
Expected: PR created; the `validate-scenarios.yml` CI workflow runs and goes green. (Handle PR/merge via `superpowers:finishing-a-development-branch` after CI passes.)

---

## Self-Review (plan vs spec)

**1. Spec coverage**

| Spec section | Task that implements it |
| --- | --- |
| Scenario contract (`scenario.yaml`, lines 49–78) | Task 1, Step 4 (verbatim) |
| `inject.{sh,ps1}` — break (lines 88–96) | Task 2 |
| `remediate.{sh,ps1}` — manual fallback (lines 98–113) | Task 3 |
| `validate.{sh,ps1}` — health probe (lines 115–119) | Task 4 |
| `alert.bicep` — detection, 4 params, authn keys (lines 121–135) | Task 5, Step 1 |
| `query.kql` — investigation (lines 137–140) | Task 5, Step 2 |
| `README.md` — walkthrough, authn-vs-authz, code-restoration (lines 142–150) | Task 6 |
| Generated artifacts regenerated, never hand-edited (lines 152–160) | Task 1 (Steps 5–7), Task 5 (Step 4), Task 7 (Step 4) |
| Testing & acceptance (lines 162–174) | Task 7 (Steps 1–4) + per-task `validate-scenarios.sh` gates |
| Out of scope: no `identity.bicep` change, one remediate action (lines 176–183) | Honored — no task touches `identity.bicep`; single `restore-federated-credential` action |

**2. Placeholder scan:** No `TODO`/`TBD`/"handle errors appropriately"/"similar to Task N" — every code/file step contains complete, verbatim content.

**3. Type/name consistency (verified across tasks):**
- Folder/id: `workload-identity-break` everywhere; `id` == folder name (validator requirement).
- FIC name: `${WORKLOAD}-fed-cred` (sh) / `$Workload-fed-cred` (ps1) / `${workloadName}-fed-cred` (bicep README snippet) — all resolve to `srelab-fed-cred`.
- Identity name: `${WORKLOAD}-id` / `srelab-id`.
- SA subject: `system:serviceaccount:workshop:workshop-app` in `remediate.sh`/`.ps1`, matching `identity.bicep`.
- Audience: `api://AzureADTokenExchange` consistently.
- Remediate action: `restore-federated-credential` in manifest (Task 1) — unique vs `cosmos-rbac-removal`'s `restore-cosmos-rbac` (validator's duplicate-action check).
- Alert resource name: `${workloadName}-workload-identity-auth-errors`; `signal.alertName: workload-identity-auth-errors` in the manifest (metadata, consistent).
- Aggregator symbol `workloadIdentityBreakAlert` / module name `alert-workload-identity-break` — matches `kebabToCamel(id)` + `alert-${id}` from the generator.
- Alert/query authn filter keys identical between `alert.bicep` and `query.kql`: `AADSTS70021`, `No matching federated identity`, `ManagedIdentityCredential`, `AADSTS`.

No gaps found.

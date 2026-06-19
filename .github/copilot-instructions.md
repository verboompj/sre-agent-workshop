# Copilot Instructions — SRE Agent Workshop

## Project Overview

A hands-on workshop teaching how the **Azure SRE Agent** detects, diagnoses, and remediates infrastructure faults. The pattern in every track: deploy real Azure infrastructure from code → inject a realistic fault → watch the agent investigate → apply a controlled fix. This is teaching material — clarity and a believable failure story matter more than production hardening.

The repo hosts **two parallel tracks**:

- **AKS track** (cloud-native, the original): lives at the **repo root** (`infra/`, `k8s/`, `src/`, `docs/`, `scripts/`). Fault = remove a CosmosDB RBAC role assignment; the agent files a GitHub issue for `@copilot` to fix in Bicep.
- **VM track** (enterprise migration): self-contained under `workshops/vm/`. Windows Server + IIS, Bastion-first access, approval-gated remediation scripts.

`workshops/aks/README.md` is only a pointer — AKS assets intentionally stay at the repo root for compatibility. `workshops/README.md` is the track index.

## Architecture

### AKS track
- **Bicep** (`infra/bicep/main.bicep`): orchestrates modules in order `monitoring → aks → cosmosdb → identity`, then defines **2 alerts inline** in `main.bicep` (not in modules).
- **App** (`src/app/server.js`): Express, 3 endpoints — `/`, `/health`, `/items`. `/health` **intentionally does not check DB connectivity** (so liveness stays green while `/items` fails). Auth to CosmosDB is via `@azure/identity` `DefaultAzureCredential` + AKS workload identity — there are **no connection strings**.
- **K8s** (`k8s/`): namespace `workshop`, ServiceAccount `workshop-app`, Deployment + Service both named `web-app` (2 replicas). Pods carry label `azure.workload.identity/use: "true"`.

### VM track (`workshops/vm/`)
- **Bicep** (`workshops/vm/infra/bicep/main.bicep`): orchestrates `monitoring → network → vm → identity → alerts`. Deploys 2 Windows VMs with IIS, a VNet/NSG, an **Azure Bastion** host (VMs have **no public IPs**), VM Insights, scheduled-query alerts (disk/IIS/CPU), and a constrained Reader/Monitoring-Reader UAMI for investigation tooling.
- **Scripts** (`workshops/vm/scripts/`): `scenarios/` inject faults, `remediation/` are the only allowed fixes, `validation/` smoke-tests, `access/` opens Bastion tunnels.
- **Tools** (`workshops/vm/tools/`): `invoke-vm-investigation` produces a visible reasoning chain (`Observe → Investigate → Correlate → Hypothesis → Propose → AwaitApproval → Execute → Validate → Postmortem`); `invoke-approved-remediation` is the approval gate; `invoke-vm-run-command` runs constrained VM commands.
- Runtime artifacts (traces, postmortems, `actions-audit.log`) are written to `workshops/vm/output/` (gitignored except `.gitkeep`).

## Build & Validation Commands

There is **no unit-test or lint framework**. Validation is Bicep-centric (these are exactly what CI runs):

```bash
# Validate AKS Bicep (syntax/compile)
az bicep build --file infra/bicep/main.bicep --stdout > /dev/null
# Validate VM Bicep
az bicep build --file workshops/vm/infra/bicep/main.bicep --stdout > /dev/null
```

- `infra/bicep/main.json` is a **generated ARM artifact** — edit `.bicep`, never the `.json`.
- App: Node `>=20`, only `npm start` (`node server.js`); the runnable build is the container image (built in CI, not locally).
- Pre-flight checks: `bash scripts/setup.sh` (AKS) / `workshops/vm/scripts/setup.sh` (VM). Teardown: `scripts/cleanup.sh`.

## Workflows — deploy is manual, validate is automatic

The deploy/validate split is the single most important workflow fact:

| Workflow | Trigger | Notes |
|---|---|---|
| `deploy-infra.yml` | **`workflow_dispatch` only** | AKS infra. Inputs: `location`, `workloadName`. |
| `deploy-app.yml` | **`workflow_dispatch` only** | AKS app. Substitutes `${AZURE_CLIENT_ID}`, `${COSMOSDB_ENDPOINT}`, and the `OWNER` image placeholder via `sed`; waits on `deployment/web-app`. |
| `deploy-vm-infra.yml` | **`workflow_dispatch` only** | VM infra. Needs secret `VM_ADMIN_PASSWORD`. |
| `validate-infra.yml` | push to `main` + PR on `infra/**` | `az bicep build` + what-if (when creds present). |
| `validate-vm-infra.yml` | push to `main` + PR on `workshops/vm/infra/**` | `az bicep build` + what-if. |
| `publish-image.yml` | `workflow_dispatch` + push to `main` on `src/**` | Publishes `ghcr.io/<owner-lowercased>/sre-agent-workshop/app:latest` (+ `:sha`). |

- Deploys **do not auto-trigger on push** — pushing infra changes only runs the `validate-*` what-if; the actual deploy is dispatched manually so participants pick region/workload explicitly.
- Azure jobs auth with the `AZURE_CREDENTIALS` secret (service-principal JSON). Repo variables `AZURE_LOCATION` / `WORKLOAD_NAME` override the defaults.
- Note: `docs/knowledge/operational-guidelines.md` still says infra deploys "after merge" — that pre-dates the manual-dispatch split; trust the workflow files.

## Key Conventions

### Bicep / Infrastructure
- Resource names follow `{workloadName}-{type}`. Defaults: AKS `srelab` (`srelab-aks`, `srelab-id`), VM `srelabvm` (`srelabvm-vm01`, RG `rg-srelabvm`).
- CosmosDB uses the **NoSQL (Core) API** with `@azure/cosmos` — **not** MongoDB. The account name gets a deterministic 4-char `uniqueString(resourceGroup().id)` suffix (e.g. `srelab-cosmos-a1b2`).
- The CosmosDB role assignment in `identity.bicep` uses **inline `resourceId()` construction** (not an `existing` reference) to avoid ARM caching that silently skips the assignment on re-deploy.
- Alerts are `Microsoft.Insights/scheduledQueryRules` (**log-based, not metric**). AKS alerts query `KubePodInventory` and `ContainerLog` (v1 schema).

### Fault-injection target (AKS)
- `infra/bicep/modules/identity.bicep` → the `cosmosRoleAssignment` resource (Cosmos DB Built-in Data Contributor, role id `…000002`) is **the thing Module 5 deletes** to break the app. Restoring it is the fix the agent/`@copilot` produces. Keep it clearly marked.

### VM remediation: the approval gate
- The SRE Agent **never runs remediation directly**. Every fix goes through `invoke-approved-remediation.{sh,ps1}`, which requires a change ticket matching `^(CHG|INC)-[0-9]+$` plus a typed `APPROVE`, maps the action name to `scripts/remediation/<action>.{sh,ps1}`, and appends a JSON line to `output/actions-audit.log`. Allowed actions are an explicit allowlist (`cleanup-disk`, `cleanup-temp`, `start-iis-app-pool`, `stop-cpu-runaway`).

### Dual-shell scripting (bash + PowerShell)
- Every operational script/tool ships **both** a bash `.sh` and a PowerShell `.ps1`. When adding or changing one, update its peer.
- Script basenames (`scenarios/`, `remediation/`, `access/`, `validation/`) are identical across shells. **Tool** basenames are not: bash is kebab-case (`invoke-approved-remediation.sh`) while PowerShell is PascalCase Verb-Noun (`Invoke-ApprovedRemediation.ps1`).

### Break-and-fix loop (AKS)
1. Remove `cosmosRoleAssignment` from `identity.bicep` (and delete it live), restart pods.
2. `/items` returns HTTP 500 with RBAC/Forbidden errors; `/health` stays green.
3. The `http-500-errors` scheduled-query alert fires (matches `ContainerLog` for `RBAC`, `Forbidden`, `Failed to read items from CosmosDB`, `StatusCode: 500`).
4. SRE Agent investigates → opens a GitHub issue assigned to `@copilot`.
5. `@copilot` restores the Bicep role assignment and opens a PR.
6. Merge → dispatch **Deploy Infrastructure** → role restored → app recovers.

## SRE Agent operational guidelines
`docs/knowledge/operational-guidelines.md` is uploaded to the SRE Agent as a knowledge file. Core rule: **never make direct Azure changes** (no `az`/portal edits) — always create a GitHub issue for `@copilot` to fix in Bicep, preserving incident → issue → PR → deploy traceability.

## Repo tooling: the `.squad/` system (not workshop content)
`.squad/`, `.github/agents/squad.agent.md`, `.copilot/skills/`, and all `.github/workflows/squad-*.yml` + `sync-squad-labels.yml` belong to **"Squad"**, a multi-agent orchestration framework used to *develop* this workshop. It is **not** part of the workshop deliverable — don't confuse the `squad-*` workflows with the deploy/validate workflows above. `.squad/log/`, `sessions/`, `orchestration-log/`, and `decisions/inbox/` are gitignored runtime state; some append-only state files use `merge=union` (see `.gitattributes`).

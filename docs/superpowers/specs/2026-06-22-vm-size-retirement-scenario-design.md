# Design — VM Scenario: `vm-size-retirement`

**Date:** 2026-06-22
**Track:** `vm`
**Status:** Approved (brainstorming) — ready for implementation plan

## Problem & Goal

The existing VM-track scenarios (`cpu-runaway`, `disk-full`, `iis-app-pool`) all teach
**runtime guest-OS faults** detected by an Azure Monitor metric/log alert and fixed through the
approval gate. This scenario adds a different, higher-level SRE capability: **impact analysis
driven by an Azure Service Health signal**.

The kickoff is an **Azure Service Health "service / SKU retirement" advisory** announcing that a
VM **size** is being retired. The SRE Agent's job is to **identify every affected service under
its control** — i.e. enumerate, via **Azure Resource Graph (ARG)**, all VMs in its resource group
running a retiring size — and then drive an **approval-gated resize migration** to a current
family. This validates the "identify all affected services" capability the workshop wants to
showcase, using only real, reproducible Azure resources (no fakes).

The scenario is rated **intermediate**, severity **2** (proactive advisory, not an outage).

## Background — two facts that shape the design

1. **Azure Service Health events cannot be injected on demand.** Microsoft generates
   Service Health retirement/health-advisory events; there is no API to fabricate one into a
   subscription's Activity Log. So the *trigger* must be **simulated** (see "Simulated kickoff"),
   while the genuinely valuable part — inventory + migration — runs against real resources.
2. **The famous lightweight retirement (Basic SKU Public IP) is past its creation cutoff.** New
   Basic public IPs cannot be created after 2025-03-31, so `inject` could not reproducibly plant
   them, and faking the SKU is out of scope. **VM size retirements are the chosen target**: they
   are real, announced, **still creatable today**, enumerable via ARG
   (`properties.hardwareProfile.vmSize`), and migratable by **resize** — a disruptive,
   reboot-causing operation that is the canonical fit for this track's approval gate + CHG ticket.

### Affected vs target sizes

- **Retiring set (affected):** the **DSv2 family** — `Standard_DS1_v2`, `Standard_DS2_v2`
  (real retirement guidance exists; still creatable).
- **Migration target:** `Standard_D2s_v5` (current, GA in all three allowed regions —
  `eastus2`, `swedencentral`, `australiaeast`). Implementation verifies region availability and
  quota; `Standard_D2as_v5` is the documented fallback target.
- The main workshop VM `srelabvm-vm01` is `Standard_B2s` — **not** in the retiring set, so it is
  never touched by the inventory or the migration.

## Simulated kickoff & production wiring (staying true to the Service Health premise)

Because a real Service Health event can't be injected, the scenario reproduces the signal **and**
documents the real production path so attendees learn the actual mechanism:

- **Simulated payload (workshop):** `inject` emits a realistic **Service Health Activity-Log
  event** JSON (category `ServiceHealth`, `incidentType: ActionRequired`, impacted service
  `Virtual Machines`, the retiring size, a future retirement deadline) to stdout and to
  `service-health-advisory.json`, rendered with the real subscription/RG/region. The attendee
  pastes it into the SRE Agent as the incident kickoff — exactly the content a real advisory
  carries.
- **Production reference (real wiring):** a committed, locally-validated `service-health-alert.bicep`
  declares the production **Activity Log alert** (`Microsoft.Insights/activityLogAlerts`, scope =
  subscription, condition on `category == ServiceHealth` + `incidentType`) plus an **Action Group**
  that routes the advisory to the SRE Agent's incident channel. It is a **reference** — *not* wired
  into the scenario framework (`signal` is omitted; the file is **not** named `alert.bicep`), since
  Service Health alerts are subscription-scoped and can't be injected. The README's
  **"How this fires in production"** notice points to it and states plainly: in production this
  advisory arrives automatically and the agent reacts; in the workshop we simulate only the
  kickoff — everything after it (ARG inventory + approval-gated migration) is real.

## Observable shape — the inventory

After `inject`, the resource group `rg-srelabvm` contains the main VM plus **3 deallocated
"legacy" VMs** on retiring sizes, with varied, realistic tags so the ARG result reads like a real
fleet inventory:

| VM | Size | State | Tags (example) |
| --- | --- | --- | --- |
| `srelabvm-vm01` | `Standard_B2s` (current) | running | workshop baseline — **excluded** |
| `srelabvm-legacy-01` | `Standard_DS1_v2` | deallocated | `env=prod`, `app=billing-legacy`, `owner=unknown` |
| `srelabvm-legacy-02` | `Standard_DS2_v2` | deallocated | `env=test`, `app=reporting-legacy` |
| `srelabvm-legacy-03` | `Standard_DS1_v2` | deallocated | `env=prod`, `app=batch-legacy`, `owner=unknown` |

The agent's ARG impact-analysis query returns exactly the three `*-legacy-*` VMs.

## Scenario contract (`scenario.yaml`)

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

Notes:
- **No `signal` block** → **no `alert.bicep`** (the scaffolded `alert.bicep` is deleted). The
  generator only wires scenarios where `signal.alertModule` is set, and `validate.js` only checks
  `alert.bicep` when `signal` is present, so an alert-less scenario is fully supported. This is the
  first scenario in the repo without a wired alert.
- The remediate `action` `migrate-vm-size` is **unique within the VM track** and its script
  basename equals the action (the approval gate resolves actions by globbing
  `scenarios/*/<action>.sh`).

## Components

All files live in `workshops/vm/scenarios/vm-size-retirement/`. Each shell/PowerShell pair must
exist (schema `scriptPair`), and `.sh` files must be executable. `.ps1` variants mirror the `.sh`
logic using the same `az` CLI calls (consistent with the existing VM-track scripts).

### `inject.{sh,ps1}` — plant the legacy fleet + emit the advisory (live)

- Args: `-g/--resource-group` (default `rg-srelabvm`), `-w/--workload` (default `srelabvm`).
- Idempotent/repeatable: for each of the 3 legacy VMs, **create it on the retiring size if absent,
  else resize it back to the retiring size** (so the scenario can be re-run after a migration).
- Creation: `az vm create` into the **existing** VNet/subnet (`srelabvm-vnet`/`srelabvm-subnet`),
  **no public IP** (`--public-ip-address ""`), no per-NIC NSG (`--nsg ""`), minimal **Ubuntu LTS**
  image, smallest Standard SSD OS disk, `--generate-ssh-keys`. VMs are inventory-only and never
  logged into. Creates run with `--no-wait` then `az vm wait --created`, after which each VM is
  **deallocated** (`az vm deallocate`) to minimise cost.
- After planting, **render and emit the Service Health advisory**: substitute the real
  subscription ID, RG, region, retiring size, and a future retirement date into the advisory
  payload; write it to `service-health-advisory.json` and print it to stdout with a one-line
  instruction to paste it into the SRE Agent.

### `service-health-advisory.json` — committed simulated payload

- A realistic Service Health Activity-Log event (category `ServiceHealth`, `eventSource
  ServiceHealth`, `incidentType ActionRequired`, `impactedServices` = `Virtual Machines`, title +
  communication describing the size retirement and the migration deadline, `trackingId`).
- Committed with example values; `inject` writes a rendered copy with the live
  subscription/RG/region.

### `migrate-vm-size.{sh,ps1}` — approval-gated migration (live)

- Invoked **only** through `tools/invoke-approved-remediation.sh` /
  `Invoke-ApprovedRemediation.ps1` (CHG/INC ticket + `APPROVE` + audit entry). The SRE Agent never
  resizes directly.
- Accepts the gate's `--resource-group` and `--vm-name` flags; **ignores `--vm-name`** and instead
  **discovers all affected VMs itself** (every VM in the RG whose size is in the retiring set) so a
  single approved action migrates the whole fleet.
- For each affected VM: `az vm resize --size Standard_D2s_v5`. Idempotent (VMs already on the target
  are skipped). Resizing a **deallocated** VM is the least-constrained path; VMs remain deallocated
  afterwards.

### `validate.{sh,ps1}` — migration check

- Args: `-g/--resource-group` (default `rg-srelabvm`).
- Query the RG for any VM whose size is in the retiring set. **Exit 0 when zero remain**
  (migration complete); non-zero otherwise. (Distinct from the other VM scenarios' guest-OS health
  probes — this scenario's success criterion is a control-plane inventory state.)

### `query.kql` — investigation (Azure Resource Graph)

- An **Azure Resource Graph** query (run via the agent's ARG capability / `az graph query`), with a
  header comment noting it is ARG, not Log Analytics:
  ```kusto
  Resources
  | where type =~ 'microsoft.compute/virtualMachines'
  | where resourceGroup =~ 'rg-srelabvm'
  | extend vmSize = tostring(properties.hardwareProfile.vmSize)
  | where vmSize in~ ('Standard_DS1_v2', 'Standard_DS2_v2')
  | project name, vmSize, resourceGroup, location, tags
  | order by name asc
  ```

### `service-health-alert.bicep` — production wiring reference (not wired, not deployed)

- A self-contained, locally-validated (`az bicep build`) reference declaring:
  - `Microsoft.Insights/actionGroups` routing to the SRE Agent / on-call.
  - `Microsoft.Insights/activityLogAlerts` (location `global`, `scopes: [subscription().id]`,
    condition `category == ServiceHealth` + `properties.incidentType == ActionRequired`, optional
    impacted-service filter `Virtual Machines`) wired to the action group.
- Params are self-descriptive (`alertScope`, `actionGroupName`, `tags`, …) and intentionally do
  **not** follow the framework's `alert.bicep` contract, because it is a production reference rather
  than a scenario signal. A top-of-file comment states this clearly. **Not** named `alert.bicep`, so
  CI's `alert.bicep`-globbed bicep build does not touch it; it is validated locally during
  implementation.

### `README.md` — attendee walkthrough

Mirrors the structure of the other VM scenarios, plus the production notice:

1. **Overview** — the Service Health retirement premise and the "identify all affected services"
   goal.
2. **How this fires in production** (the notice) — Service Health advisory → Activity Log alert
   (`service-health-alert.bicep`) → Action Group → SRE Agent; explicit statement that the workshop
   simulates only the kickoff because Service Health events can't be injected.
3. **Inject** — run `inject.sh`; observe the 3 legacy VMs and the emitted advisory JSON.
4. **Kickoff** — paste the advisory into the SRE Agent.
5. **Investigate** — the agent runs the ARG impact analysis (`query.kql`) and lists the affected
   VMs.
6. **Remediate** — operator runs
   `Invoke-ApprovedRemediation -Action migrate-vm-size -ChangeTicket CHG-12345`.
7. **Validate** — `validate.sh` confirms zero VMs remain on a retiring size.
8. Link to `../../docs/90-watch-agent-workflow.md`.

## Generated / shared artifacts (regenerated, never hand-edited)

- `workshops/vm/scenarios/INDEX.md` — gains a row.
- `workshops/vm/README.md` scenario table (between the `BEGIN/END SCENARIOS` markers) — gains a row.
- `workshops/vm/infra/bicep/modules/scenario-alerts.bicep` — **unchanged** (this scenario has no
  wired alert; the generator skips it).

Produced by `scripts/validate-scenarios.sh --write`; CI fails on drift.

## Docs touch-ups (track consistency)

- `workshops/vm/docs/02-configure-incident-response.md` — add a `migrate-vm-size` row to the
  "Available actions" table so the approval-gate action list stays complete.

## Testing & acceptance

- `scripts/validate-scenarios.sh` prints `Scenario validation passed`.
- `cd scripts/scenario-tools && npm test` — all tests still pass.
- `az bicep build --file workshops/vm/infra/bicep/main.bicep --stdout` succeeds (the regenerated
  aggregator is unchanged — verifies the alert-less scenario causes no drift).
- `az bicep build --file workshops/vm/scenarios/vm-size-retirement/service-health-alert.bicep
  --stdout` succeeds (the production reference is valid Bicep).
- All `.sh` scripts are executable; both `.sh` and `.ps1` exist for inject/validate/migrate.
- `validate-scenarios.yml` CI is green on the PR.

> Runtime behaviour (creating/resizing live VMs) is **not** part of automated CI; it is validated
> manually per the workshop flow. No live Azure changes are made during implementation.

## Out of scope

- No new track, no schema changes, no scenario-tooling changes — the scenario is self-contained.
- No wired alert / `alert.bicep` — the kickoff is the simulated advisory; the production signal is
  a documented reference only.
- No second remediation action (single `migrate-vm-size`).
- The legacy VMs are inventory-only Ubuntu hosts; no application/guest workload runs on them, and
  they are never started beyond the create→deallocate step.

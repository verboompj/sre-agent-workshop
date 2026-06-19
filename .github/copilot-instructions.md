# Copilot Instructions — SRE Agent Workshop

## What this repository is

A hands-on workshop that teaches **Azure SRE Agent** incident response through a
**multi-track, scenario-based framework**. A *track* is a self-contained workshop variant
(a different Azure platform); a *scenario* is a self-contained, reproducible fault a learner
injects, then watches the SRE Agent detect, diagnose, and drive to remediation via a GitHub
issue → `@copilot` PR → deploy (GitOps).

Two tracks ship today:

- **`workshops/aks/`** — AKS + CosmosDB + a Node.js app (the original tutorial).
- **`workshops/vm/`** — a VM / enterprise-migration track with an approval-gated remediation model.

The framework is meant to be **extended by contributors** — `CONTRIBUTING.md` is the contract.
When adding or changing anything, prefer the scenario tooling and keep the per-track structure intact.

## Repository structure

```
docs/                         # Shared, track-agnostic concept layer (00-what / 01-why / 02-how)
workshops/<track>/
  README.md                   # Track landing (+ generated scenario table between markers)
  docs/                       # Module walkthroughs
  infra/bicep/                # Bicep; main.bicep calls generated modules/scenario-alerts.bicep
  scenarios/<id>/             # Self-contained fault scenarios (+ generated INDEX.md)
  knowledge/                  # SRE Agent knowledge files (aks: operational-guidelines.md)
  ...                         # Track-specific: aks has k8s/, src/app/; vm has tools/
schemas/scenario.schema.json  # The scenario manifest contract (JSON Schema draft 2020-12)
scripts/
  new-scenario.sh             # Scaffold a scenario from the canonical template
  validate-scenarios.sh       # Validate + (--write) regenerate indexes/aggregators
  scenario-tools/             # Node ESM tooling behind the wrappers
.github/workflows/            # Per-track deploy/validate + scenario CI + docs-freshness
```

## The scenario framework (read before touching scenarios)

A scenario lives in `workshops/<track>/scenarios/<id>/` and is driven by a `scenario.yaml`
manifest. Tooling under `scripts/scenario-tools/` (Node ESM; `bin/{validate,generate,new-scenario}.js`,
`lib/{validate,generate,paths}.js`) validates manifests and **generates** derived artifacts.
Never hand-edit a generated artifact — change the manifest and regenerate.

- **Scaffold:** `scripts/new-scenario.sh <track> <id> "Title"` (`<track>` ∈ `aks|vm`, `<id>` kebab-case).
- **Validate / regenerate:** `scripts/validate-scenarios.sh --write` then `scripts/validate-scenarios.sh`
  (must print `Scenario validation passed`).
- **Unit tests:** `cd scripts/scenario-tools && npm test` (Node `--test`).
- **Generated (do not edit by hand):**
  - `workshops/<track>/infra/bicep/modules/scenario-alerts.bicep` — aggregator that wires every
    scenario's `alert.bicep`, passing the track's scope resource id.
  - `workshops/<track>/scenarios/INDEX.md`.
  - The scenario table in each track `README.md`, between `<!-- BEGIN SCENARIOS -->` / `<!-- END SCENARIOS -->`.
- **Tracks are a closed set** in `scripts/scenario-tools/lib/paths.js` (`TRACKS`): `aks → scopeParam
  clusterId`, `vm → scopeParam logAnalyticsResourceId`. Adding a track edits this **and** the schema
  `track` enum **and** adds a `validate-<track>-infra.yml` workflow (see `CONTRIBUTING.md` → "Add a track").

### Scenario manifest (`scenario.yaml`)

Required: `id` (== folder name), `title`, `track` (== parent dir), `summary`, `severity` (0–4),
`inject`, `validate`, `docPage`. Common optional: `estimatedMinutes`, `difficulty`
(`beginner|intermediate|advanced`), `learningObjectives`, `signal` (`alertModule`/`alertName`),
`remediate` (list of `{action, bash, powershell, description}`), `investigation` (`query`).
The authoritative contract is `schemas/scenario.schema.json`.

### Scenario conventions

- **Always ship both shells:** `inject`, `validate`, and every `remediate` action need a `.sh`
  *and* a `.ps1`. `.sh` scripts must be executable.
- **`alert.bicep`** must declare exactly `location`, `workloadName`, `tags`, `scopeResourceId`,
  and bind `scopes: [scopeResourceId]`. If a scenario needs no alert, omit `signal` and delete `alert.bicep`.
- **`action` naming is track-dependent.** The **VM** approval gate
  (`workshops/vm/tools/invoke-approved-remediation.sh` / `Invoke-ApprovedRemediation.ps1`) resolves
  `--action` by globbing `scenarios/*/<action>.sh`, so on the VM track the remediation script basename
  **must equal** the action and actions are unique per track. The **AKS** track has no such gate and
  deliberately uses `action: restore-cosmos-rbac` with files `remediate.{sh,ps1}` — do **not** enforce
  basename==action globally.
- **Avoid drift:** any manifest change requires re-running `--write`; CI fails if `INDEX.md`, the
  aggregator, or the README table are stale.

## Track specifics

### AKS (`workshops/aks/`)

- Resource names follow `{workloadName}-{type}` (default `srelab`). CosmosDB uses the **NoSQL (Core)
  API** with `@azure/cosmos` (NOT MongoDB); endpoint `https://{name}-cosmos-{suffix}.documents.azure.com:443/`.
- Auth chain: Pod → K8s OIDC → federated credential → UAMI → CosmosDB RBAC. Namespace `workshop`,
  ServiceAccount `workshop-app` (must match the federated credential in `infra/bicep/modules/identity.bicep`).
- Alerts are `Microsoft.Insights/scheduledQueryRules` (log-based) over `ContainerLog`/`KubePodInventory`.
  The shipped `cosmos-rbac-removal` scenario's `inject`/`remediate` remove/recreate the
  `cosmosRoleAssignment` in `infra/bicep/modules/identity.bicep` (built with inline `resourceId()` to
  avoid ARM caching); its http-500 alert is generated into the aggregator.
- App: `src/app/server.js` (Express; `/`, `/health`, `/items`; `DefaultAzureCredential`). Image at
  `ghcr.io/<owner>/sre-agent-workshop/app:latest`; the `OWNER` placeholder in `k8s/deployment.yaml`
  is substituted by the publish workflow.

### VM (`workshops/vm/`)

- Remediation is **approval-gated**: `tools/invoke-approved-remediation.sh` (PowerShell:
  `Invoke-ApprovedRemediation.ps1`) maps an action to a scenario-owned script, requires a `CHG`/`INC`
  ticket plus an explicit `APPROVE`, and writes an audit entry. The SRE Agent never runs remediation directly.

## Workflows (`.github/workflows/`, shared across tracks)

- **AKS:** `deploy-aks-infra.yml` (**manual `workflow_dispatch` only** — region/workload chosen at
  deploy time), `deploy-aks-app.yml` (manual dispatch), `publish-aks-image.yml` (push on
  `workshops/aks/src/**`; GHCR, lowercased owner), `validate-aks-infra.yml` (push/PR on
  `workshops/aks/infra/**`; syntax + what-if).
- **VM:** `deploy-vm-infra.yml`, `validate-vm-infra.yml`.
- **Framework:** `validate-scenarios.yml` — schema check, unit tests, drift check, and `az bicep build`
  on every `alert.bicep` + aggregator.
- **Docs freshness:** `sre-docs-freshness.md` is the gh-aw **source**; `sre-docs-freshness.lock.yml`
  (and `.github/aw/actions-lock.json`) are generated — edit the `.md` and recompile with `gh aw compile`.
- Deploy is intentionally **manual**; validation runs on push/PR. In the Actions tab, display names are
  track-qualified (e.g. **Deploy AKS Infrastructure** vs **Deploy VM Infrastructure**) — refer to them by
  those names in docs. AKS deploy/validate workflows authenticate with the `AZURE_CREDENTIALS` secret;
  `publish-aks-image.yml` uses `GITHUB_TOKEN`/GHCR.

## Docs & the SRE Agent

- **Concept layer:** `docs/00-what-is-sre-agent.md`, `01-why-sre-agent.md`, `02-how-it-works.md`
  (track-agnostic).
- **Operational guidelines:** `workshops/aks/knowledge/operational-guidelines.md` is uploaded to the SRE Agent
  as a knowledge file. It mandates **no direct Azure changes** — every fix goes through a GitHub issue
  assigned to `@copilot`, which opens a PR; an operator then **manually** triggers the track's deploy
  workflow. Keep this file consistent with the actual (manual-deploy) model.

## Contributing

`CONTRIBUTING.md` is the contract: the 6-step scenario flow, what CI enforces, and the add-a-track
procedure. Follow it (and the tooling) rather than wiring scenarios in by hand.

# Contributing

Thanks for extending the SRE Agent Workshop! The most common contribution is **a new
scenario**. Scenarios are self-contained folders governed by a manifest contract, so adding
one requires **no edits to shared infrastructure or tooling**.

## Prerequisites

- Node.js 22+ (for the scenario tooling under `scripts/scenario-tools/`)
- Azure CLI with Bicep (`az bicep version`)
- PowerShell 7+ if you want to run the `.ps1` script variants

## Add a scenario (the 6-step flow)

1. **Scaffold** from the canonical template:

   ```bash
   scripts/new-scenario.sh <track> <scenario-id> "Human Title"
   # e.g. scripts/new-scenario.sh vm memory-leak "Memory Leak"
   ```

   `<track>` is `aks` or `vm`; `<scenario-id>` is kebab-case and becomes the folder name.

2. **Fill in `scenario.yaml`.** Required: `id` (== folder name), `title`, `track`,
   `summary`, `severity` (0–4), `inject`, `validate`, `docPage`. Recommended: `estimatedMinutes`,
   `difficulty`, `learningObjectives`, `signal`, `remediate`, `investigation`. The full
   contract lives in [`schemas/scenario.schema.json`](schemas/scenario.schema.json).

3. **Implement the scripts** — both `.sh` and `.ps1` for `inject`, `validate`, and each
   `remediate` action. Keep each remediation script named after its `action` (the VM approval
   gate resolves actions by globbing `scenarios/*/<action>.sh`, so action names are unique
   per track).

4. **Author `alert.bicep` and `query.kql`.** `alert.bicep` must declare exactly
   `location`, `workloadName`, `tags`, and `scopeResourceId`, and bind `scopes: [scopeResourceId]`.
   The generator wires it into the track aggregator automatically. If your scenario needs no
   alert, drop `signal` from the manifest and delete `alert.bicep`.

5. **Write `README.md`** — the attendee walkthrough (inject → observe → investigate →
   remediate → validate).

6. **Generate + validate**:

   ```bash
   scripts/validate-scenarios.sh --write   # regenerates INDEX.md, aggregator, README table
   scripts/validate-scenarios.sh           # must print "Scenario validation passed"
   chmod +x workshops/<track>/scenarios/<id>/*.sh
   ```

Open a PR. CI (`validate-scenarios.yml`) re-runs the schema check, unit tests, drift check,
and `az bicep build` on every `alert.bicep` + aggregator.

## What CI enforces

- `scenario.yaml` validates against the schema.
- `id` == folder name; `track` == parent track directory.
- Required files exist; `.sh` scripts are executable; both `.sh` and `.ps1` exist for
  `inject` / `validate` / each `remediate` action.
- Every `alert.bicep` is wired into the generated `scenario-alerts.bicep`.
- `INDEX.md` and the README scenario table are regenerated and unchanged (no drift).
- Remediation action names are unique within a track.

## Add a track (advanced)

Tracks are the closed set in `scripts/scenario-tools/lib/paths.js` (`TRACKS`). To add one
(e.g. `appservice`):

1. Add an entry to `TRACKS` with its alert `scopeParam` (the Bicep param name the aggregator
   passes into each scenario's `scopeResourceId`, e.g. an App Service resource ID).
2. Create `workshops/<track>/` with `README.md` (include the
   `<!-- BEGIN SCENARIOS -->` / `<!-- END SCENARIOS -->` markers), `docs/`, `infra/bicep/`,
   and `scenarios/`.
3. If the track deploys alerts, have `infra/bicep/main.bicep` call the generated
   `modules/scenario-alerts.bicep` with the track's scope resource ID.
4. Add the track's enum value to `schemas/scenario.schema.json` (`properties.track.enum`).
5. Add a workflow `validate-<track>-infra.yml` mirroring the existing ones, repathed to
   `workshops/<track>/infra/**`.
6. Scaffold a first scenario and run `scripts/validate-scenarios.sh --write`.

## Style

- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `test:`).
- Keep scenarios self-contained: prefer adding files under `scenarios/<id>/` over editing
  shared tooling.

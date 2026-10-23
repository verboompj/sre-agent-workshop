# Scenario Framework & Repository Future-Proofing — Design

- **Date:** 2026-06-10
- **Status:** Approved (design); pending implementation plan
- **Author:** @JoranBergfeld (with Copilot CLI)

## 1. Problem

The workshop has grown from one fault scenario into several, and they are scattered
across the repository with no shared contract:

- **VM track** (`workshops/vm/`) half-implements a scenario pattern, but each scenario
  is smeared across ~7 locations: a numbered doc page (`docs/0X-scenario-*.md`), an
  injector (`scripts/scenarios/inject-*`), a remediation script (`scripts/remediation/*`),
  an alert resource inside the shared `alerts.bicep` monolith, a hardcoded `case "$SCENARIO"`
  allow-list + KQL switch in the investigation tooling, and two README tables. Naming is
  inconsistent (`inject-disk-full` vs `stop-iis-app-pool`).
- **AKS track** lives at the repository top level (`infra/`, `k8s/`, `src/`, `docs/`) and
  has a single fault (CosmosDB RBAC removal) with no scenario folder at all — it is woven
  into the linear module narrative as manual `az` commands in `docs/05-break-it.md`, an
  infra edit, and an inline alert in `main.bicep`.
- The two tracks are structured completely differently, there is no shared scenario
  contract, no scenario template, and no `CONTRIBUTING` guide.

Adding a new use case therefore means hunting across the repo and editing several shared,
hand-maintained files — high friction and error-prone, especially for external contributors.

## 2. Goals & Non-Goals

### Goals
- One **unified scenario contract** across both tracks.
- Each scenario is a **self-contained, pluggable folder** (vertical slice).
- **Self-serviceable for external contributors**: strong template, authoring docs, and
  CI validation so a new scenario can arrive as a single, well-formed PR.
- Make both tracks **physically symmetric** under `workshops/<track>/`.
- Add a **shared conceptual layer** explaining what the SRE Agent is, why to use it, and
  how it works.
- Add a **weekly agentic workflow** that watches the upstream SRE Agent docs and opens a
  review PR when our conceptual docs drift.

### Non-Goals
- No change to the existing `.squad/` multi-agent system or its `squad-*.yml` workflows.
- No rewrite of the actual fault logic of existing scenarios — only repackaging.
- No change to Azure resource architecture (AKS, CosmosDB, VM/IIS) beyond relocation.

## 3. Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Scope | Both tracks unified under one shared scenario contract, including refactoring AKS |
| Restructure depth | Full move now: relocate AKS into `workshops/aks/`, physically symmetric tracks |
| Primary authors | External contributors / community → strong templates, docs, CI validation |
| Packaging model | Approach 1: self-contained folders + machine-readable manifest + scaffold + CI |
| Conceptual content | Add a shared "what / why / how" layer separate from track setup and scenarios |
| Docs-freshness agent | GitHub Agentic Workflows (`gh-aw`), weekly, opens a draft review PR |

## 4. Target Repository Structure

Content splits into three layers: **shared concept → per-track setup → pluggable scenarios.**

```
sre-agent-workshop/
├── README.md                       # Vision, "why SRE Agent", track index, quick start
├── CONTRIBUTING.md                 # NEW: how to add a scenario / a track
├── docs/                           # LAYER 1 — SHARED, track-agnostic concept
│   ├── 00-what-is-sre-agent.md     #   what it is
│   ├── 01-why-sre-agent.md         #   why use it (MTTR, value)
│   ├── 02-how-it-works.md          #   how it works (autonomy, GitHub loop)
│   └── knowledge/
│       └── operational-guidelines.md   # uploaded to the agent (stays shared)
├── schemas/
│   └── scenario.schema.json        # NEW: validates every scenario.yaml
├── scripts/                        # repo-level tooling
│   ├── new-scenario.sh             # NEW: scaffold a scenario from _template
│   └── validate-scenarios.sh       # NEW: local mirror of CI validation
└── workshops/
    ├── README.md                   # track index
    ├── aks/
    │   ├── README.md               # track overview + module index
    │   ├── docs/                   # LAYER 2 — SETUP modules only
    │   │   ├── 00-prerequisites.md
    │   │   ├── 01-deploy-infrastructure.md
    │   │   ├── 02-deploy-application.md
    │   │   ├── 03-onboard-sre-agent.md
    │   │   ├── 04-configure-incident-response.md
    │   │   ├── 90-watch-sre-agent.md
    │   │   └── 99-cleanup.md
    │   ├── infra/bicep/   k8s/   src/app/   scripts/
    │   └── scenarios/              # LAYER 3 — pluggable use cases
    │       ├── _template/          # copy-me scaffold
    │       ├── cosmos-rbac-removal/   # migrated "Break It" scenario
    │       └── INDEX.md            # GENERATED from manifests
    └── vm/
        ├── README.md  docs/  infra/bicep/  scripts/  tools/
        └── scenarios/
            ├── _template/  disk-full/  iis-app-pool/  cpu-runaway/
            └── INDEX.md            # GENERATED
```

Key moves:
- **AKS fully relocates** under `workshops/aks/`. The single "Break It" RBAC fault becomes
  the first AKS *scenario* (`cosmos-rbac-removal/`), giving AKS the same pluggable model
  and room to grow more scenarios.
- **Top-level `docs/`** is repurposed for the shared concept layer + `knowledge/`.
- **Setup docs renumber** to `00–04` + `90-watch-sre-agent` + `99-cleanup`; "watch the
  agent" and "cleanup" become generic per-track bookends, with scenarios slotting between.
- **`.github/workflows/`** stays repo-global; path triggers/working-dirs update to
  `workshops/<track>/…` and workflows are renamed for clarity (e.g. `deploy-aks-infra.yml`).
  The `.squad/*` workflows are untouched.

## 5. The Scenario Contract

Every scenario is one self-contained folder with a fixed shape. Adding a scenario means
creating one folder (via the scaffold) — no edits to shared monoliths.

```
scenarios/<scenario-id>/
├── scenario.yaml      # manifest — single source of truth
├── README.md          # the walkthrough (replaces the old numbered doc page)
├── inject.sh / .ps1   # fault injection
├── remediate.sh / .ps1# approval-gated fix (one or more actions)
├── validate.sh / .ps1 # recovery check
├── alert.bicep        # this scenario's alert rule, as a Bicep module
└── query.kql          # investigation query (optional)
```

### 5.1 Manifest (`scenario.yaml`)

Validated by `schemas/scenario.schema.json`. Example:

```yaml
id: disk-full
title: "Disk Full"
track: vm
summary: "C: fills from runaway temp files until free space < 10%."
severity: 2
estimatedMinutes: 20
difficulty: beginner
learningObjectives:
  - "Attribute disk pressure to a specific path"
  - "Approve a constrained cleanup remediation"
signal:
  alertModule: alert.bicep
  alertName: "${workloadName}-vm-disk-pressure"
inject:        { bash: inject.sh, powershell: inject.ps1 }
remediate:
  - { action: cleanup-disk, bash: remediate.sh, powershell: remediate.ps1, description: "Remove C:\\Temp\\diskfill" }
validate:      { bash: validate.sh, powershell: validate.ps1 }
investigation: { query: query.kql }
docPage: README.md
```

Required fields: `id`, `title`, `track`, `summary`, `severity`, `inject`, `validate`,
`docPage`. `id` must be kebab-case and equal the folder name. `track` must be one of the
known tracks. `remediate`, `investigation`, `signal`, `estimatedMinutes`, `difficulty`,
and `learningObjectives` are optional but recommended.

### 5.2 Eliminating the three scattering points

- **Generic investigation tooling.** `invoke-vm-investigation.{sh,ps1}` drops its hardcoded
  `case "$SCENARIO"` allow-list and per-scenario KQL switch; it instead reads `scenario.yaml`
  and `query.kql` from the named scenario folder. New scenarios require zero tool edits.
- **Alert aggregation.** Each scenario owns `alert.bicep` (a Bicep module). A generated
  `infra/bicep/modules/scenario-alerts.bicep` aggregator `module`-references each scenario's
  alert (Bicep cannot glob, so the list is generated, not hand-edited). `new-scenario.sh`
  wires the new module in and CI checks parity between `scenarios/*/alert.bicep` and the
  aggregator. The current monolithic `alerts.bicep` is decomposed into per-scenario modules.
- **Generated index.** `scenarios/INDEX.md` and the track README scenario table are produced
  from manifests by tooling and verified in CI — never hand-maintained.

### 5.3 Naming normalization

Scenario scripts standardize to `inject` / `remediate` / `validate` (today the VM track
mixes `inject-disk-full`, `stop-iis-app-pool`, `cleanup-temp`, `stop-cpu-runaway`). Each
ships both `.sh` and `.ps1`.

## 6. Contributor Enablement & CI

- **`scripts/new-scenario.sh <track> <id>`** copies `_template/`, substitutes placeholders
  (id, title, track), and wires the alert aggregator and index. Output is a ready-to-edit
  folder plus a checklist of what to fill in.
- **`scripts/validate-scenarios.sh`** runs the same checks locally that CI runs.
- **`.github/workflows/validate-scenarios.yml`** runs on PRs touching `workshops/**/scenarios/**`
  or the schema, enforcing:
  - `scenario.yaml` validates against `schemas/scenario.schema.json`.
  - `id` equals folder name; `track` matches the parent track directory.
  - Required files present and the `.sh`/`.ps1` scripts are executable.
  - Both `.sh` and `.ps1` variants exist for `inject` / `remediate` / `validate`.
  - The scenario's `alert.bicep` is wired into the aggregator.
  - `INDEX.md` and the README scenario table are regenerated and unchanged (no drift).
- **`CONTRIBUTING.md`** documents the end-to-end "add a scenario" flow so external PRs are
  self-serviceable: scaffold → fill manifest → write README + scripts + alert → validate →
  open PR. It also covers "add a track" at a high level.

## 7. Docs-Freshness Agentic Workflow

A weekly GitHub Agentic Workflow (`gh-aw`) — distinct from the `.squad/` system — that keeps
the shared concept layer aligned with upstream Azure SRE Agent documentation. It is
philosophically consistent with `operational-guidelines.md`: it never edits docs silently;
it opens a draft PR for human review.

`.github/workflows/sre-docs-freshness.md` (compiled to a sibling `.lock.yml`):

```yaml
---
name: SRE Agent Docs Freshness
on:
  schedule: [{ cron: "0 7 * * 1" }]   # Mondays 07:00 UTC
  workflow_dispatch:
engine: copilot
permissions: { contents: read }
network:
  allowed: [defaults, learn.microsoft.com, "*.azure.com"]
tools:
  web-fetch:
  bash: ["git"]
safe-outputs:
  create-pull-request:
    title-prefix: "[docs-freshness] "
    labels: [documentation, automated]
    draft: true
---
# Compare our shared concept docs (docs/00,01,02 + knowledge/operational-guidelines.md)
# against the upstream Azure SRE Agent docs. If anything is outdated/renamed/removed, or a
# notable new capability exists, edit the affected files minimally and open ONE draft PR
# summarizing what changed upstream (with cited URLs). If everything is current, do nothing.
```

- **Watch scope:** only the shared concept layer (`docs/00–02` + `operational-guidelines.md`)
  — the track-agnostic prose most likely to drift. Scenario walkthroughs are out of scope
  (they describe our code, not upstream).
- **Upstream sources:** `learn.microsoft.com/azure/sre-agent/*` and the SRE Agent overview
  pages. (Exact URL list to be confirmed during spec review — see Open Questions.)
- **Safety:** read-only permissions + sanitized `safe-outputs`; opens a **draft** PR, never
  commits to a doc directly. Requires a `.gitattributes` entry
  `.github/workflows/*.lock.yml linguist-generated=true merge=ours` and committing both the
  `.md` source and the compiled `.lock.yml`.

## 8. Migration & Phasing

Each phase is independently shippable; ordered lowest-risk-first, with the riskiest
relocation isolated.

| Phase | Scope | Risk |
|---|---|---|
| **1. Scenario framework** | `schemas/scenario.schema.json` + `_template` + `new-scenario.sh` + `validate-scenarios.sh` + `validate-scenarios.yml`. No file moves. | Low — purely additive |
| **2. VM track adoption** | Refactor VM's 3 scenarios into folders + manifests; make investigation tooling manifest-driven; decompose `alerts.bicep` into per-scenario modules + aggregator; generate INDEX. | Medium — VM-local |
| **3. AKS relocation** | Move AKS → `workshops/aks/`; convert "Break It" → `cosmos-rbac-removal/` scenario; update + rename workflows; fix doc links. | **Highest** — live paths/workflows/attendee links |
| **4. Shared concept layer** | Repurpose top-level `docs/` into concept pages; rewrite top README around tracks + concept. | Low |
| **5. Docs-freshness agent** | Author `gh-aw` workflow, `gh aw compile`, add `.gitattributes`, commit `.md` + `.lock.yml`. | Low — independent |

### Phase 3 safety measures
- Update every workflow `paths:` trigger and `working-directory` to `workshops/aks/…`.
- Rename AKS workflows for clarity (`deploy-aks-infra.yml`, `deploy-aks-app.yml`,
  `publish-aks-image.yml`) and verify `AZURE_CREDENTIALS` usage is preserved.
- Leave short redirect stubs at old top-level doc paths (and old README anchors) pointing to
  the new locations so in-flight attendee links don't break.
- Verify the federated-credential namespace/service-account assumptions still hold after the
  move (no functional change intended).

## 9. Error Handling & Edge Cases

- **Incomplete scenario PR:** CI fails with a precise message naming the missing/invalid
  field or file. `new-scenario.sh` reduces this by generating a complete skeleton.
- **Alert aggregator drift:** CI compares the generated aggregator against the scenario set
  and fails on mismatch, directing the author to re-run `new-scenario.sh`/the generator.
- **Index drift:** CI regenerates `INDEX.md`/README table and fails if the committed copy
  differs.
- **Docs-freshness false positives:** Output is a *draft* PR a human reviews; if upstream is
  unchanged the agent makes no PR. No autonomous merge.
- **`.lock.yml` not regenerated:** CI (or a `gh aw compile --validate` check) flags a stale
  compiled workflow.

## 10. Testing & Validation Strategy

- Reuse existing build/validate workflows (`validate-infra.yml`, `validate-vm-infra.yml`) for
  Bicep; ensure the decomposed alert modules + aggregator still `bicep build` cleanly.
- New `validate-scenarios.yml` is the contract's test harness; `scripts/validate-scenarios.sh`
  lets contributors run it locally before pushing.
- Smoke-test `new-scenario.sh` by scaffolding a throwaway scenario and asserting CI passes on
  it unmodified (template must be valid by construction).
- Manually dispatch `sre-docs-freshness` via `workflow_dispatch` once to confirm it runs,
  respects the network allowlist, and produces a draft PR (or no-op) as designed.

## 11. Open Questions

- Exact upstream URL set for the docs-freshness agent (overview + how-to pages under
  `learn.microsoft.com/azure/sre-agent/`).
- Final workflow renaming scheme and whether to keep backward-compatible workflow names.
- Whether `cosmos-rbac-removal` keeps its current manual-`az` injection or gains
  `inject.sh`/`remediate.sh` scripts to match the VM scenarios' script-driven model
  (recommended: add scripts for symmetry, keep the narrative in README).

## 12. References

- GitHub Agentic Workflows (`gh-aw`): https://github.github.io/gh-aw/
- gh-aw frontmatter reference: https://github.github.io/gh-aw/reference/frontmatter/
- Azure SRE Agent docs: https://learn.microsoft.com/azure/sre-agent/
- Existing VM scenario assets: `workshops/vm/scripts/{scenarios,remediation}`, `workshops/vm/infra/bicep/modules/alerts.bicep`
- Existing AKS fault: `infra/bicep/modules/identity.bicep`, `docs/05-break-it.md`

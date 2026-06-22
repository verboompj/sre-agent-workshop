# Design: GitHub issue-logging docs refresh + docs-readiness agentic workflow

**Date:** 2026-06-22
**Status:** Approved (brainstorming)

## Problem

Workshop onboarding docs tell learners to enable GitHub issue creation via
**Capabilities → Tools → DevOps → enable `CreateGitHubIssue` / `FetchGitHubIssue` / …**.
The Azure SRE Agent product has changed: GitHub issue, PR, and workflow operations are now
configured as a **connector** (**Builder → Connectors → Add connector → GitHub OAuth connector**,
OAuth or PAT). The old Tools toggle path no longer matches the product, so learners get stuck on
"issue logging within GitHub."

Verified against authoritative upstream docs:

- `learn.microsoft.com/azure/sre-agent/setup-github-connector` (updated 2026-06-04) — GitHub
  connector via **Builder → Connectors**, OAuth/PAT, for issue/PR/workflow operations.
- `learn.microsoft.com/azure/sre-agent/connect-source-code` (updated 2026-05-19) — the source-code
  connection (Code card) is separate; connecting it auto-creates a GitHub OAuth connector.
- `sre.azure.com/docs/get-started/create-and-setup` and `.../automate-incidents` — current setup
  page (Code/Logs/Azure Resources/Knowledge cards) and incident flow (Builder → Incident platform,
  Builder → Incident response plans).

Why the drift went unnoticed: the existing `sre-docs-freshness` gh-aw workflow **deliberately
excludes** track setup docs and scenario walkthroughs (`workshops/.../docs/...`) — exactly where the
outdated instructions live (`03-onboard-sre-agent.md`).

Track findings:

- **AKS** and **App Service** Module 3 (`03-onboard-sre-agent.md`) contain the identical outdated
  "Enable the GitHub Tool" section.
- **VM** has no onboarding module and does **not** use GitHub issue logging at all — remediation is
  purely approval-gated (`Invoke-ApprovedRemediation`); no `knowledge/` dir, no `@copilot`
  references. VM learners likely borrowed AKS Module 3 and hit the broken section.

## Goals

1. Correct the GitHub issue-logging instructions across tracks using a **single canonical shared
   doc** that all tracks reuse (no triplicated steps).
2. Add an **agentic workflow** that guards documentation readiness — both **internal integrity** and
   **upstream accuracy** — for the docs the existing freshness workflow does not cover.

## Non-goals

- Changing the remediation philosophy (issue → `@copilot` for AKS/App Service; approval-gated for VM).
- Building a VM onboarding module (chose a lightweight clarifying note instead).
- A blocking PR-CI doc gate or a deterministic link-linter script (the ask is an agentic,
  PR-opening workflow; a deterministic helper script is a possible future enhancement, explicitly
  out of scope here).
- Re-checking scenario generated-artifact drift (`INDEX.md`, `scenario-alerts.bicep`, README
  `BEGIN/END SCENARIOS` tables) — already owned by `validate-scenarios.yml`.

## Sharing mechanism (constraint)

This repo renders plain Markdown on GitHub — there is **no docs-site generator** (no
mkdocs/docusaurus), so Markdown transclusion/`include` is not available. "Reuse across workshops"
is therefore implemented as **one canonical shared doc + each track links to it** (single source of
truth), not copy-pasted blocks.

## Deliverable 1 — Docs refresh

### 1a. New shared doc: `docs/connect-github-to-sre-agent.md`

Track-agnostic, merged "Connect GitHub" content (Approach B). Sections:

1. **Intro** — the two GitHub integrations: code connection (investigation context) vs the GitHub
   **connector** (issue/PR/workflow actions). Connecting code auto-creates a GitHub OAuth
   connector; you still add/verify the connector for issue actions.
2. **Connect your code repository** — Code card → **+** → GitHub → **Auth** or **PAT** → pick repo
   from dropdown → **Add repository** → green check. Read-only code understanding.
3. **Set up the GitHub connector (issue logging)** — **Builder → Connectors → Add connector →
   GitHub OAuth connector** → OAuth (Sign in) or PAT → confirm **Connected**.
4. **Verify** — chat prompt *"List recent issues from `<owner>/<repo>`"* (and/or create a test issue).
5. **Note** — issue-based tracks rely on the connector (agent files an issue, assigns `@copilot`);
   approval-gated tracks can skip the connector.

Cite the upstream URLs above so the readiness/freshness workflows have anchors.

### 1b. AKS + App Service `workshops/<track>/docs/03-onboard-sre-agent.md`

- Consolidate the existing **"Connect Your Code Repository"** + dead **"Enable the GitHub Tool"**
  sections into one short **"Connect GitHub"** section that:
  - keeps 2–3 lines of track-specific *why* (code understanding + the issue → `@copilot`
    remediation loop), and
  - **links to `../../../docs/connect-github-to-sre-agent.md`** for the step-by-step.
- Fix stale references from "the GitHub **tool**" → "the GitHub **connector**" in the
  "Upload Knowledge Files → What This Does" and the "Why this matters" callouts.
- Leave "Verify Setup" as-is (it already points to **Builder → Connectors**).

### 1c. VM `workshops/vm/docs/02-configure-incident-response.md`

- Add a short callout: remediation on this track is **approval-gated** via
  `Invoke-ApprovedRemediation`; the SRE Agent does **not** create GitHub issues or use a GitHub
  connector here. If you set the agent up via the shared doc, **skip** the connector step.

## Deliverable 2 — `sre-docs-readiness` gh-aw workflow

New source file `.github/workflows/sre-docs-readiness.md`, compiled to `.lock.yml` with
`gh aw compile` (gh-aw compiler v0.77.5, `engine: copilot`). Complements (does not replace)
`sre-docs-freshness`.

### Frontmatter

- `on:` weekly `schedule:` on a **different day** than freshness (freshness = Mon 07:00 UTC; use a
  later weekday, e.g. Thu 07:00 UTC) **+ `workflow_dispatch`**.
- `permissions: contents: read` (read-only agent; safe-outputs job holds write perms).
- `network.allowed:` `defaults`, `learn.microsoft.com`, `*.azure.com`.
- `tools:` `web-fetch` + `bash` with a **read-only** allowlist (`git`, `grep`, `find`, `ls`, `cat`,
  `test`).
- `safe-outputs.create-pull-request:` `draft: true`, `title-prefix: "[docs-readiness] "`,
  `labels: [documentation, automated]`, `reviewers: [JoranBergfeld]`, `max: 1`.

### Body / instructions

- **In scope — internal integrity** (all of): `docs/*.md` (excluding `docs/superpowers/**`),
  `workshops/*/README.md`, `workshops/*/docs/**.md`, `workshops/*/scenarios/*/README.md`. Checks:
  relative links resolve; each track README module list matches files in its `docs/`; per-track
  links to `docs/connect-github-to-sre-agent.md` resolve; `TODO`/`TBD`/placeholder scan; stale
  section references (e.g. a lingering "Enable the GitHub Tool").
- **In scope — upstream accuracy** (web-fetch `learn.microsoft.com` + `*.azure.com`): the track
  setup docs that describe live product UI — `workshops/*/docs/03-onboard-sre-agent.md`,
  `workshops/*/docs/0?-configure-incident-response.md`, `workshops/*/docs/90-watch*.md` — and the
  shared `docs/connect-github-to-sre-agent.md`.
- **Out of scope:** `docs/00-02` + `operational-guidelines.md` (freshness owns upstream), generated
  scenario artifacts (`validate-scenarios.yml` owns drift), `docs/superpowers/**`.
- **Output rule:** make minimal edits, open **one** draft PR grouping findings by category with
  cited source URLs; if everything is current and consistent, do nothing (no PR).

### Boundary note in `sre-docs-freshness.md`

Add one line to the freshness "Scope" section clarifying it does **not** own
`docs/connect-github-to-sre-agent.md` or any `workshops/.../docs/**` file (the readiness workflow
does), to prevent future overlap. Recompile its `.lock.yml`.

## Validation

- `gh aw compile` regenerates both `*.lock.yml` files and updates `.github/aw/actions-lock.json`
  (requires the `gh aw` CLI extension; install if missing). CI fails if lock files are stale.
- `scripts/validate-scenarios.sh` stays green (no scenario changes expected).
- Manually verify every changed/added relative doc link resolves.
- Optionally trigger `sre-docs-readiness` via `workflow_dispatch` to smoke-test once merged.

## Risks

- `gh aw` CLI availability in the dev environment — install the gh extension before compiling.
- `reviewers: [JoranBergfeld]` requires that account to have repo access (repo owner — fine).
- Schedule overlap with freshness — mitigated by complement scoping + a different cron day.

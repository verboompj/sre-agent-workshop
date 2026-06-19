# Design — AKS Scenario: `workload-identity-break`

**Date:** 2026-06-19
**Track:** `aks`
**Status:** Approved (brainstorming) — ready for implementation plan

## Problem & Goal

The AKS track has a single scenario (`cosmos-rbac-removal`), which teaches an
**authorization** failure (a missing CosmosDB RBAC role assignment) remediated through the
Bicep/`deploy-aks-infra.yml` GitOps path. To move the AKS track toward "multiple scenarios
fully," we add a second, complementary scenario that teaches a different failure class with a
**distinct alert signal**.

`workload-identity-break` injects an **authentication** failure: the workload's federated
identity credential is deleted, so pods can no longer exchange their projected ServiceAccount
token for an Azure AD token. The app keeps passing liveness (`/health`) but every `/items`
request returns HTTP 500 with an `AADSTS70021: No matching federated identity record found`
error. The scenario is deliberately contrasted with `cosmos-rbac-removal` (authn vs authz) and
is rated **advanced**.

## Background — the identity chain

Defined in `workshops/aks/infra/bicep/modules/identity.bicep`:

- **UAMI** `${workloadName}-id` (e.g. `srelab-id`).
- **Federated Identity Credential (FIC)** `${workloadName}-fed-cred`, parented to the UAMI, with:
  - `issuer`: the AKS OIDC issuer URL,
  - `subject`: `system:serviceaccount:workshop:workshop-app`,
  - `audiences`: `api://AzureADTokenExchange`.
- **CosmosDB role assignment** (the `cosmos-rbac-removal` target — untouched here).

The pod authenticates as: projected SA token → (FIC trust) → AAD token for the UAMI →
CosmosDB. Removing the FIC breaks the **token-exchange** step (authentication), before any
RBAC/authorization check is reached.

## Observable behaviour

| Endpoint | Before | After fault |
| --- | --- | --- |
| `/health` | 200 healthy | 200 healthy (does not check the DB) |
| `/items` | 200 (`[]` or items) | 500 — `Failed to connect to CosmosDB: … AADSTS70021 …` |

`server.js` logs `Failed to read items from CosmosDB: <err.message>` where `err.message`
carries the AAD token-exchange error (`AADSTS70021` / `No matching federated identity record`).

## Scenario contract (`scenario.yaml`)

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

The remediate `action` (`restore-federated-credential`) is unique within the AKS track
(`cosmos-rbac-removal` uses `restore-cosmos-rbac`).

## Components

All files live in `workshops/aks/scenarios/workload-identity-break/`. Each shell/PowerShell
pair must exist (schema `scriptPair`), and `.sh` files must be executable.

### `inject.{sh,ps1}` — break (live)

- Discover RG (default `rg-srelab`, overridable via `-g/--resource-group`) and workload name
  (default `srelab`, overridable via `-w/--workload`).
- `az identity federated-credential delete --name "${WORKLOAD}-fed-cred" --identity-name "${WORKLOAD}-id" --resource-group "$RG" --yes`
  (no-op-safe if already deleted).
- `kubectl rollout restart deployment/web-app -n workshop` + `rollout status --timeout=90s`
  to force a fresh token exchange that now fails.
- Mirrors the structure/flags of `cosmos-rbac-removal/inject.sh`.

### `remediate.{sh,ps1}` — manual fallback fix (live)

- Discover RG, workload name, and the AKS cluster (`az aks list -g "$RG" --query "[0].name"`).
- Fetch the OIDC issuer: `az aks show -g "$RG" -n "$CLUSTER" --query oidcIssuerProfile.issuerUrl -o tsv`.
- Re-create the FIC:
  ```
  az identity federated-credential create \
    --name "${WORKLOAD}-fed-cred" --identity-name "${WORKLOAD}-id" --resource-group "$RG" \
    --issuer "$OIDC_ISSUER" \
    --subject "system:serviceaccount:workshop:workshop-app" \
    --audiences "api://AzureADTokenExchange"
  ```
- `kubectl rollout restart deployment/web-app -n workshop` + status.
- This is the **manual fallback**; the primary remediation in the workshop narrative is the
  `@copilot` PR restoring the `federatedCredential` block in `identity.bicep` followed by a
  manual `Deploy AKS Infrastructure` run.

### `validate.{sh,ps1}` — health probe

- Resolve the LoadBalancer IP of `svc/web-app` in `workshop`.
- `curl /items`; exit 0 on HTTP 200, non-zero otherwise. Identical contract to
  `cosmos-rbac-removal/validate.sh`.

### `alert.bicep` — detection (generated into the aggregator)

- Declares **exactly** `location`, `workloadName`, `tags`, `scopeResourceId` (per the
  framework contract); binds `scopes: [scopeResourceId]` (the AKS cluster ID passed by the
  generated `scenario-alerts.bicep`).
- Resource `Microsoft.Insights/scheduledQueryRules`, name
  `${workloadName}-workload-identity-auth-errors`, severity 3, `PT5M`/`PT5M`.
- Query scopes to `workshop` namespace containers (via `KubePodInventory` join, like the
  existing alert) and filters `ContainerLog` `LogEntry` for **authn-specific** strings so it is
  distinct from the existing `http-500-errors` alert:
  `AADSTS70021`, `No matching federated identity`, `ManagedIdentityCredential`, `AADSTS`.

> Note: because `server.js` funnels all `/items` errors through the same log line, the existing
> `http-500-errors` alert may also fire. The new alert's authn-specific keys give the agent a
> precise signature that points at token exchange / federated identity rather than RBAC.

### `query.kql` — investigation

Same authn-specific filter as the alert, projecting `TimeGenerated, LogEntry`, `top 50 by
TimeGenerated desc` — mirrors `cosmos-rbac-removal/query.kql`.

### `README.md` — attendee walkthrough

Mirrors the structure of `cosmos-rbac-removal/README.md`: Overview → narrative scenario →
Verify current state → Make the change (remove the `federatedCredential` block from
`identity.bicep` + delete the live FIC) → Watch it break (`/health` green, `/items` 500 with
AADSTS70021) → What's happening under the hood (token-exchange sequence) → What happens next
(agent files an issue, `@copilot` PR **restores the `federatedCredential` block in
`identity.bicep`**, operator redeploys) → Next step link to `../../docs/90-watch-sre-agent.md`.
Emphasises the **authn-vs-authz** contrast with `cosmos-rbac-removal`.

## Generated / shared artifacts (regenerated, never hand-edited)

- `workshops/aks/infra/bicep/modules/scenario-alerts.bicep` — gains a module wiring the new
  `alert.bicep` with the camel-cased symbol, scoped to `clusterId`.
- `workshops/aks/scenarios/INDEX.md` — gains a row.
- `workshops/aks/README.md` scenario table (between the `BEGIN/END SCENARIOS` markers) — gains
  a row.

These are produced by `scripts/validate-scenarios.sh --write`; CI fails on drift.

## Testing & acceptance

- `scripts/validate-scenarios.sh` prints `Scenario validation passed`.
- `cd scripts/scenario-tools && npm test` — 13/13 still pass.
- `az bicep build --file workshops/aks/infra/bicep/main.bicep --stdout` succeeds (exercises the
  regenerated aggregator including the new `alert.bicep`).
- `az bicep build` on the scenario's `alert.bicep` succeeds.
- All `.sh` scripts are executable; both `.sh` and `.ps1` exist for inject/validate/remediate.
- `validate-scenarios.yml` CI is green on the PR.

> Runtime behaviour (actual fault injection on a live cluster) is **not** part of automated CI;
> it is validated manually per the workshop flow. No live Azure changes are made during
> implementation.

## Out of scope

- No `identity.bicep` changes are committed while building the scenario — the
  `federatedCredential` block already exists and models desired state. The README narrative has
  the attendee remove it (and `@copilot` restore it) during the workshop run.
- No new track, no schema changes, no tooling changes — the scenario is self-contained.
- No second remediation action (single `restore-federated-credential`).

# Scenario: Canary Release Regression 🐤💥

> Track: `appservice` · Scenario id: `canary-bad-release`

## What breaks

A "v2" release of the shop is rolled out to the **`staging` deployment slot** and given **50% canary traffic**. The v2 build does two things:

- **Functional regression:** `/products` runs `SELECT Id, Name, Price, Sku …`, but `Sku` does not exist in `dbo.Products`. SQL raises `Invalid column name 'Sku'`, the handler catches it and returns **HTTP 500**.
- **Visible reskin (didactic marker):** the landing page (`/`) flips from **green `v1 · stable`** to **red `v2 · canary`** with a red "Add to cart" button, so you can *see* which slot served you.

Because traffic is split 50/50 and each request is independently routed, roughly **half** of `/products` calls fail while:

- `/health` stays **green** (it never touches SQL), so the slot remains in rotation.
- `/` returns **200** on both slots (it catches the query error and renders a red error block), so the red theme is always visible.
- The **production** slot is completely unaffected.

A naive uptime check on `/health` misses this entirely — that's the point.

## Prerequisites

- The App Service track infrastructure deployed **with the `staging` slot** (run **Deploy App Service Infrastructure**, then **Deploy App Service Application**, which seeds the good build to the slot).
- Local tools for inject/remediate: `az`, the **.NET 10 SDK** (`dotnet`), and `zip`.

## Inject the fault

```bash
./inject.sh                      # bash / Linux
# ./inject.ps1                   # PowerShell / Windows
# options: -g <resource-group>  -w <workload>
```

This builds `Program.regression.cs`, zip-deploys it to the `staging` slot, and sets `staging=50` traffic routing.

## Validate impact

```bash
./validate.sh
```

Issues ~12 cookie-less `GET https://<host>/products`. A live canary returns a mix of `200`/`500`, so **any** non-200 ⇒ exit non-zero (degraded). After remediation, all `200` ⇒ exit 0.

Also open `https://<host>/` and refresh a few times: you'll flip between the **green v1** and **red v2** shop, the red one showing the catalog error.

## Let the SRE Agent remediate

The `canary-5xx` alert (`alert.bicep`) fires when more than three `/products` requests fail in a 5-minute window (App Insights `AppRequests`, scoped to the Log Analytics workspace). The agent is expected to:

1. **Detect** the partial outage from the alert.
2. **Investigate** with `query.kql` — correlate the failures to the `staging` slot's `AppRoleInstance` and drill `AppExceptions` for `Invalid column name 'Sku'`.
3. **Mitigate operationally** — clear the canary traffic routing (the `restore-traffic` action).
4. **Fix durably** — file a GitHub issue; `@copilot` opens a PR that reverts the `Sku` query back to `SELECT Id, Name, Price …` (the cosmetic red reskin is harmless and need not change). Merging it and re-running **Deploy App Service Application** redeploys the corrected build.

## Manual remediation (facilitator fallback)

```bash
./remediate.sh
```

Clears traffic routing (100% back to production) and redeploys the good `src/` build to the `staging` slot.

## Cleanup

Re-run `./remediate.sh` (idempotent) to clear any leftover routing, or simply run the track's **Cleanup** module to delete the resource group.

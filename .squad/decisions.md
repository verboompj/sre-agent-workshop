# Squad Decisions

## Active Decisions

### Web App Design — CosmosDB Auth & Health Check Strategy
**Author:** Linus | **Date:** 2026-04-12 | **Status:** Implemented

1. **AAD credentials only, no connection strings.** The CosmosClient uses `aadCredentials: new DefaultAzureCredential()`. This is the only auth path — there's no fallback. When the role assignment is removed, the app fails cleanly with an auth error the SRE Agent can read.

2. **Health check ignores the database.** `/health` returns 200 unconditionally. This keeps pods in Running state even after the fault injection, so errors show up as 500s on `/items` rather than pod restarts. The SRE Agent sees a healthy pod with failing requests — a more realistic and diagnosable scenario.

3. **Verbose error messages on /items.** The raw SDK error (e.g., `AuthorizationFailed`) is included in the 500 response body and logged to stdout. This gives the SRE Agent clear signal when reading pod logs.

4. **Pinned dependency versions.** All three dependencies use exact versions for reproducibility across attendee environments.

---

### Bicep Architecture — Alert Rule in main.bicep
**Author:** Rusty | **Date:** 2025-07-14 | **Status:** Implemented

The alert rule (`scheduledQueryRules`) lives directly in `main.bicep` rather than in `modules/monitoring.bicep`. This keeps the dependency chain linear: Monitoring → AKS → Alert. Anyone adding new alert rules should add them to `main.bicep` (not the monitoring module) if they scope to AKS.

---

### Workflow & Script Design Choices
**Author:** Rusty | **Date:** 2026-04-12 | **Status:** Implemented

1. Used actual Bicep resource names (e.g., `{workloadName}-id` for UAMI), not task-spec names.

2. **`sed` over `envsubst`** for manifest substitution — more surgical targeting of specific placeholders without replacing K8s-native patterns.

3. **deploy-infra.yml captures outputs as JSON** — single Azure call, all values captured via `jq` parsing.

4. **deploy-app.yml polls for external IP** — AKS LoadBalancer IP assignment can take 30-60s; polls 12 times at 5s intervals.

5. **Workflows use env vars for DRY defaults** — `WORKLOAD` and `LOCATION` set once in `env:` with fallback defaults.

---

### Architecture Review — Final Quality Gate
**Author:** Danny | **Date:** 2026-04-12 | **Scope:** Full workshop implementation

#### 🛑 Critical Issues (Will Break the Workshop)

1. **CosmosDB API Mismatch — SQL SDK vs MongoDB API**
   - CosmosDB created with `kind: 'MongoDB'` but app uses `@azure/cosmos` (SQL/NoSQL SDK)
   - `@azure/cosmos` cannot read MongoDB-API databases; `sqlRoleAssignments` don't grant MongoDB access
   - **Fix:** Change `cosmosdb.bicep` from MongoDB → NoSQL (Core) API: `kind: 'GlobalDocumentDB'`, remove `EnableMongo`, change `mongodbDatabases` → `sqlDatabases`, change `collections` → `containers` with partition key `/id`

2. **Container Image Name Mismatch**
   - `publish-image.yml` pushes to `ghcr.io/{owner}/sre-agent-workshop/app:latest`
   - `deployment.yaml` references `ghcr.io/{owner}/sre-agent-workshop:latest` (missing `/app`)
   - **Fix:** Add `/app` to deployment.yaml image reference

#### ⚠️ Moderate Issues

3. **No Alert Fires for Fault Scenario**
   - Only Container Restart alert exists; but `/health` passes, pods don't restart, alert never fires
   - **Fix:** Add log-based alert for HTTP 500 errors or CosmosDB auth failures

4. **`AZURE_SUBSCRIPTION_ID` Secret Never Used**
   - Prerequisites tell attendees to create it, but no workflow references it
   - **Fix:** Remove from prerequisites doc

5. **Module 1 Doc: Wrong Role Name**
   - Says "Cosmos DB Built-in Data **Reader**" but identity.bicep uses **Contributor** (role ID `00000000-0000-0000-0000-000000000002`)
   - **Fix:** Change to "Data Contributor"

6. **Module 4: Wrong AKS Cluster Name**
   - Manual alert command references `managedclusters/aks-srelab` but cluster is named `srelab-aks`
   - **Fix:** Change to `srelab-aks`

#### 💡 Suggestions (Nice-to-Haves)

7. **`POD_NAMESPACE` Not Injected** — Add via downward API in deployment
8. **Application Insights Connection String Unused** — Consider removing or adding App Insights SDK
9. **Module 5 Error Response Mismatch** — Docs show `"details"` field, app only returns `"error"`

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

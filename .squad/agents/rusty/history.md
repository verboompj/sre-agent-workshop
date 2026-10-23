# Rusty — History

## Core Context

- **Project:** A hands-on workshop introducing Azure SRE Agent capabilities within AKS through guided scenarios and Bicep infrastructure
- **Role:** Infra Dev
- **Joined:** 2026-04-12T08:49:21.225Z

## Learnings

<!-- Append learnings below -->

- **Bicep infra created:** 6 files under `infra/bicep/` — `main.bicep`, `main.bicepparam`, and 4 modules (`aks`, `cosmosdb`, `monitoring`, `identity`).
- **Dependency order:** Monitoring (LA + AppInsights) → AKS → CosmosDB (parallel) → Identity → Alert rule. The alert is in `main.bicep` to avoid a circular dep between monitoring and AKS.
- **CosmosDB role assignment** lives in `identity.bicep` with a clear `// WORKSHOP:` comment marking it as the fault injection target for Module 5.
- **Naming convention:** `{workloadName}-{type}` (e.g. `srelab-aks`, `srelab-cosmos`, `srelab-id`, `srelab-law`, `srelab-ai`).
- **CosmosDB SQL role assignment** uses the built-in "Cosmos DB Built-in Data Contributor" role definition ID `00000000-0000-0000-0000-000000000002`.
- **Linting:** Bicep CLI 0.42.1 validates clean (0 warnings). Connection string output removed to avoid the `outputs-should-not-contain-secrets` linter rule.
- **Regions locked:** `eastus2`, `swedencentral`, `australiaeast` via `@allowed` decorator.
- **AKS config:** 2× Standard_DS2_v2 nodes, workload identity + OIDC enabled, Azure Monitor addon, K8s 1.30.
- K8s manifests live in `k8s/` — `namespace.yaml`, `service-account.yaml`, `deployment.yaml`, `service.yaml`
- Namespace: `workshop`; ServiceAccount: `workshop-app` — these names are bound to the Bicep federated credential in `identity.bicep` and must stay in sync
- Deployment label selector: `app: web-app`; Service selector matches the same label
- Placeholders use `${VARIABLE}` syntax (`AZURE_CLIENT_ID`, `COSMOSDB_ENDPOINT`) for `envsubst` substitution at deploy time
- Container image placeholder: `ghcr.io/OWNER/sre-agent-workshop:latest`
- Workload identity requires both the SA annotation (`azure.workload.identity/client-id`) and the pod label (`azure.workload.identity/use: "true"`)
- **GitHub Actions workflows created:** 3 files under `.github/workflows/`:
  - `publish-image.yml` — builds + pushes container image to ghcr.io on `src/**` changes; uses `docker/build-push-action@v6`
  - `deploy-infra.yml` — deploys Bicep via `az deployment group create`; triggers on `workflow_dispatch` + push to `infra/**` (critical for Module 5 fault auto-deploy)
  - `deploy-app.yml` — deploys K8s manifests to AKS; uses `sed` to substitute `${AZURE_CLIENT_ID}`, `${COSMOSDB_ENDPOINT}`, and `OWNER` placeholders
- **Helper scripts created:** `scripts/setup.sh` (prerequisite checker) and `scripts/cleanup.sh` (resource group teardown with confirmation)
- **Resource name alignment:** Workflows use actual Bicep names (`-id` not `-identity`, `-cosmos`, `-aks`) to avoid lookup failures
- **deploy-infra.yml** captures Bicep outputs as JSON, parses with `jq`, and exposes them via `$GITHUB_OUTPUT` for the summary step
- **deploy-app.yml** polls for the LoadBalancer external IP (up to 60s) before printing the app URL
- Workflows use `azure/login@v2` with `AZURE_CREDENTIALS` secret (service principal JSON); `AZURE_SUBSCRIPTION_ID` is available but login via creds handles it

# Operational Guidelines

## Infrastructure as Code — No Direct Changes

All infrastructure changes MUST go through code. Never modify Azure resources directly via CLI, portal, or API during incident remediation.

**When you identify a fix:**

1. **Create a GitHub issue** describing the root cause, affected resources, and the required Bicep change
2. **Assign the issue to `@copilot`** (the Copilot coding agent) — it will pick up the issue, create a branch, make the fix, and open a PR automatically
3. After the PR is merged, an operator manually triggers the **Deploy App Service Infrastructure** workflow to apply the change (deployment is intentionally manual via `workflow_dispatch`, not automatic on merge)

**Do NOT:**
- Run `az` CLI commands to directly create, modify, or delete Azure resources
- Use the Azure portal to make manual changes
- Apply temporary fixes outside of version control
- Create branches or PRs yourself — delegate to `@copilot` via GitHub issues

**Why:** This team follows GitOps principles. All infrastructure state is defined in Bicep templates under `workshops/appservice/infra/bicep/`. Direct changes create drift between code and reality, making future incidents harder to diagnose. Using GitHub issues with `@copilot` ensures full traceability from incident → issue → PR → deployment.

## Architecture Overview

- **App Service** (`srelab-web-{suffix}`): Linux B1 plan hosting the .NET 10 shop; endpoints `/`, `/health`, `/products`
- **Azure SQL Database** (`srelab-sql-{suffix}` / `srelab-db`): catalog store, accessed passwordlessly via managed identity (no connection-string secrets)
- **Managed Identity** (`srelab-id`): UAMI assigned to the web app; granted a least-privilege contained user (`db_datareader`) in Azure SQL
- **Authentication chain**: Web App → User-Assigned Managed Identity → AAD token → Azure SQL contained user (`db_datareader`)

## Telemetry

- **Application Insights** (`srelab-ai`, workspace-based) collects requests, dependencies, and exceptions
- **Log Analytics** (`srelab-law`) also receives App Service platform logs (`AppServiceConsoleLogs`, `AppServiceHTTPLogs`) via diagnostic settings
- The shop logs failures to stdout (`AppServiceConsoleLogs`) and they surface as `AppExceptions` in App Insights

# Module 2: Deploy the Application (~30 min)

## Overview

You've got the infrastructure running. Now let's deploy the workshop web app to your App Service. The app is a simple .NET 10 shop that connects to Azure SQL using **managed identity** — no passwords, no connection strings in your code. When everything works, you'll see product catalog data flowing from the database. This is the "before" state that we'll deliberately break in Module 5.

## How the App Works

**Quick tech summary:**

- **Runtime:** .NET 10 / ASP.NET Core running on Azure App Service (Linux)
- **Three endpoints:**
  - `GET /` — Landing page showing connection status and app info
  - `GET /health` — Health check (used by App Service health probes)
  - `GET /products` — Reads the product catalog from Azure SQL using the app's managed identity
- **Authentication:** Uses `Azure.Identity` library's `DefaultAzureCredential` to automatically pick up the User-Assigned Managed Identity credentials
- **The magic:** App Service injects the UAMI token endpoint → `DefaultAzureCredential` requests an AAD token → Azure SQL validates the token against the contained database user → database access granted

This is exactly how production apps authenticate to Azure SQL in App Service — no passwords to store, no connection strings to rotate.

## Deploy via GitHub Actions

1. **Go to your fork** on GitHub → **Actions** tab
2. **Select the workflow:** `Deploy App Service Application`
3. **Click "Run workflow"** (dropdown in the upper right)
4. Fill in the workflow inputs:
   - **workloadName** (default: `srelab`) — **must match what you used in Module 1**. If you deployed infrastructure with a different name, use the same name here.
5. **Click "Run workflow"** and wait for completion (~5–8 minutes)

**What the workflow does under the hood:**

- Sets up the .NET 10 SDK
- Builds the app with `dotnet publish` (Release configuration)
- Creates a zip artifact and deploys it to the App Service via `az webapp deploy --type zip`
- Installs `sqlcmd` (go-sqlcmd) on the runner
- Runs `db/schema.sql` to seed the product catalog
- Runs `db/grant.sql` to create the contained database user for the UAMI and grant `db_datareader`

## Verify the Deployment

Check that the App Service is running:

```bash
# Get the web app name and hostname
WEB_APP=$(az webapp list --resource-group rg-srelab --query "[0].name" -o tsv)
WEB_HOST=$(az webapp show --resource-group rg-srelab --name "$WEB_APP" \
  --query defaultHostName -o tsv)
echo "App URL: https://$WEB_HOST"
```

Check the app state:

```bash
az webapp show \
  --resource-group rg-srelab \
  --name "$WEB_APP" \
  --query "{name:name, state:state, hostName:defaultHostName}" \
  -o table

# Expected output:
# Name               State    HostName
# -----------------  -------  -----------------------------------
# srelab-web-xxxx    Running  srelab-web-xxxx.azurewebsites.net
```

## Test the App

Once the deployment completes, open your browser or use `curl`:

```bash
# Test the health endpoint (should always return 200)
curl https://$WEB_HOST/health

# Expected output:
# {"status":"healthy","timestamp":"2026-04-12T10:23:45.123Z"}
```

```bash
# Test the products endpoint (reads from Azure SQL)
curl https://$WEB_HOST/products

# Expected output:
# 200 OK with a JSON array of catalog products
# e.g. [{"id":1,"name":"Widget","price":9.99}, ...]
```

```bash
# Visit the landing page in your browser
echo "Open https://$WEB_HOST in your browser"

# You should see an HTML page showing:
# - Azure SQL Status: connected
# - App name and environment
```

**Checkpoint:** If `/products` returns `200` with a product list, the managed-identity authentication chain is working:

```
App Service Web App (with UAMI assigned)
  ↓
DefaultAzureCredential (picks up UAMI via AZURE_CLIENT_ID env var)
  ↓
Azure AD (issues AAD token for the UAMI)
  ↓
Azure SQL (validates token → contained user "srelab-id" with db_datareader)
  ↓
Database Access ✓
```

## Troubleshooting

**App returns 500 on `/products` with auth error:**
```bash
# Stream the live App Service log to diagnose
az webapp log tail --resource-group rg-srelab --name "$WEB_APP"
```
Look for `401 Unauthorized` or `Login failed for user '<token-identified principal>'`. This means one of the identity/SQL-grant chain steps failed. Common causes:
- The `db/grant.sql` step didn't run or failed — re-run the **Deploy App Service Application** workflow
- The UAMI client ID isn't set in the app settings — verify with `az webapp config appsettings list --resource-group rg-srelab --name "$WEB_APP" --query "[?name=='AZURE_CLIENT_ID']"`
- The SQL server firewall is blocking the runner — check the firewall rules in the portal

**App returns 503 Service Unavailable:**
```bash
# Check App Service state and recent events
az webapp show --resource-group rg-srelab --name "$WEB_APP" --query "state"
```
If the state is not `Running`, the App Service plan may be starting. Wait 1–2 minutes and retry.

**`/health` returns 200 but `/products` returns 500:**

This confirms the app is running but the database connection is failing. Stream the logs:
```bash
az webapp log tail --resource-group rg-srelab --name "$WEB_APP"
```
Look for Azure SQL connection errors or `DefaultAzureCredential` authentication failures. Verify the schema and grant scripts ran successfully by checking the workflow run logs in GitHub Actions.

**App not updating after redeployment:**
```bash
# Restart the web app to force the new code to load
az webapp restart --resource-group rg-srelab --name "$WEB_APP"
```

## Next Step

→ **[Module 3: Onboard the Azure SRE Agent](./03-onboard-sre-agent.md)**

In the next module, you'll create an SRE Agent and teach it about your infrastructure. The agent will learn your architecture, read your code, and build the knowledge it needs to diagnose faults when things go wrong.

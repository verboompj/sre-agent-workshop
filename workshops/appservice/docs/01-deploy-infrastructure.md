# Module 1: Deploy Infrastructure (~30 min)

## Overview

This module walks you through provisioning all the Azure infrastructure for the workshop: an App Service Plan hosting a .NET 10 web app, an Azure SQL database, centralized logging and monitoring, and a managed identity for secure passwordless app-to-database authentication. All resources are defined in Bicep and deployed via a GitHub Actions workflow.

After this module completes, you'll have a fully-functional App Service and backend database ready for the application deployment in Module 2.

## What Gets Deployed

The workflow deploys the following Azure resources to your subscription. All resource names are prefixed with your `workloadName` (default: `srelabapp`):

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| Resource Group | `rg-{workloadName}` | Container for all workshop resources |
| App Service Plan | `{workloadName}-plan` | Linux B1 hosting plan for the web app |
| Web App | `{workloadName}-web-{suffix}` | .NET 10 shop; endpoints `/`, `/health`, `/products` |
| Azure SQL Server | `{workloadName}-sql-{suffix}` | Logical SQL server; AAD-only auth enabled |
| Azure SQL Database | `{workloadName}-db` | Catalog database (Basic tier, 5 DTU) |
| Log Analytics Workspace | `{workloadName}-law` | Centralized logging for the App Service platform and app |
| Application Insights | `{workloadName}-ai` | Application performance monitoring and diagnostics |
| User-Assigned Managed Identity | `{workloadName}-id` | UAMI assigned to the web app for passwordless SQL auth |
| Alert Rules | Automatic | Log-based alerts for HTTP 500 errors and app restarts (wired in the first scenario) |

**App Service Configuration:**
- **Plan:** B1 Linux (1 vCPU, 1.75 GB RAM)
- **Runtime:** .NET 10 (Linux)
- **Always On:** Enabled
- **Managed Identity:** User-Assigned (UAMI), assigned at deployment time

> **Note:** The SQL AAD administrator is set to the deploying service principal automatically by the workflow. This allows the app-deployment workflow (Module 2) to run schema migrations and managed-identity grants without extra configuration.

## Prerequisites: Register Azure Resource Providers

Before deploying, ensure the required Azure resource providers are registered on your subscription. These are needed by the various Azure services used in this workshop:

| Resource Provider | Required By |
|---|---|
| `Microsoft.Web` | App Service Plan and web app |
| `Microsoft.Sql` | Azure SQL server and database |
| `Microsoft.OperationalInsights` | Log Analytics workspace |
| `Microsoft.Insights` | Application Insights & alert rules |
| `Microsoft.ManagedIdentity` | User-Assigned Managed Identity |

> **Note:** Most of these providers are registered by default on new Azure subscriptions.

Register all providers with the Azure CLI:

```bash
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.ManagedIdentity
```

To verify registration status:

```bash
az provider show --namespace Microsoft.Web --query "registrationState" -o tsv
```

Registration is typically instant but can take up to a few minutes. Wait for all providers to show `Registered` before proceeding.

---

## Run the Deployment

Choose one of the two deployment options below. **Option A (GitHub Actions) is recommended** for the full workshop experience. Option B is useful for local testing and development.

### Option A: GitHub Actions (Recommended)

#### Step 1: Navigate to GitHub Actions

Go to your fork of the workshop repository on GitHub:
1. Click the **Actions** tab at the top
2. In the left sidebar, select **Deploy App Service Infrastructure** workflow

#### Step 2: Trigger the Workflow

1. Click the **Run workflow** button (green button on the right)
2. Configure the workflow inputs:

   - **location** (dropdown)  
     Choose your Azure region. Supported options:
     - `eastus2` (recommended for US)
     - `swedencentral` (recommended for Europe)
     - `australiaeast` (recommended for Asia-Pacific)
   
   - **workloadName** (text input)  
     Defaults to `srelabapp`. You can customize this if desired (e.g., `srelabapp-team1`). This name is used in all resource naming. **Keep this name handy — you'll need it in future modules.** Use lowercase alphanumeric only, no special characters.

3. Click **Run workflow**

#### Step 3: Monitor the Deployment

The workflow will start immediately. You'll see a yellow icon next to the workflow name while it's running. The deployment typically takes **10–15 minutes**.

**To watch the logs:**
1. Click on the workflow run (it appears at the top of the Actions list)
2. Click the **deploy** job in the left sidebar
3. Watch the steps execute in real-time

The workflow performs these steps:
- Creates the resource group (`rg-{workloadName}`)
- Resolves the deploying service principal's object ID (sets it as SQL AAD admin)
- Deploys the monitoring stack (Log Analytics + Application Insights)
- Creates the managed identity
- Deploys the Azure SQL server, `{workloadName}-db` database, and firewall rules
- Deploys the App Service Plan and web app (UAMI assigned, app settings wired)
- Outputs key resource names and URLs

**Expected final output:**
```
============================================
  Infrastructure Deployment Complete
============================================
Resource Group:  rg-srelabapp
Location:        eastus2
Web App:         srelabapp-web-xxxx
Web App URL:     https://srelabapp-web-xxxx.azurewebsites.net
SQL Server:      srelabapp-sql-xxxx
============================================
```

---

### Option B: Local CLI Deployment

Deploy infrastructure directly from your machine using the Azure CLI. This is useful for rapid testing, development iterations, or situations where you prefer manual control.

#### Prerequisites

- **Azure CLI** installed and authenticated:
  ```bash
  az --version
  az login
  ```
- **jq** installed (for parsing deployment outputs):
  - macOS: `brew install jq`
  - Linux: `apt-get install jq` or `yum install jq`
  - Windows: Download from https://stedolan.github.io/jq/download/

#### Step 1: Set Environment Variables

Replace `srelabapp` and `eastus2` with your desired workload name and location:

```bash
export WORKLOAD_NAME="srelabapp"
export LOCATION="eastus2"
```

**Supported locations:**
- `eastus2` (recommended for US)
- `swedencentral` (recommended for Europe)
- `australiaeast` (recommended for Asia-Pacific)

**Workload name guidelines:**
- Lowercase alphanumeric only (e.g., `srelabapp`, `srelabapp-team1`, `mysre123`)
- Keep it short — it's used in all resource names
- Remember this name for future modules

#### Step 2: Create the Resource Group

```bash
az group create \
  --name "rg-${WORKLOAD_NAME}" \
  --location "${LOCATION}" \
  --tags workshop=sre-agent environment=demo
```

**Expected output:**
```json
{
  "id": "/subscriptions/.../resourceGroups/rg-srelabapp",
  "location": "eastus2",
  "name": "rg-srelabapp",
  "properties": {
    "provisioningState": "Succeeded"
  }
}
```

#### Step 3: Resolve the SQL AAD Admin Object ID

The deploying service principal becomes the SQL AAD admin. Resolve its object ID:

```bash
export SQL_ADMIN_OID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || \
  az ad signed-in-user show --query id -o tsv)
echo "SQL AAD admin OID: $SQL_ADMIN_OID"
```

#### Step 4: Deploy the Bicep Template

From the repository root, run:

```bash
az deployment group create \
  --resource-group "rg-${WORKLOAD_NAME}" \
  --template-file workshops/appservice/infra/bicep/main.bicep \
  --parameters workshops/appservice/infra/bicep/main.bicepparam \
    location="${LOCATION}" \
    workloadName="${WORKLOAD_NAME}" \
    sqlAadAdminObjectId="${SQL_ADMIN_OID}" \
  --query 'properties.outputs' \
  -o json > deployment-outputs.json

cat deployment-outputs.json
```

The deployment typically takes **10–15 minutes**. You'll see progress output as resources are created.

#### Step 5: Display Deployment Outputs

After the deployment completes, parse the outputs:

```bash
echo "============================================"
echo "  Infrastructure Deployment Complete"
echo "============================================"
echo "Resource Group:  rg-${WORKLOAD_NAME}"
echo "Location:        ${LOCATION}"
echo "Web App:         $(jq -r '.webAppName.value' deployment-outputs.json)"
echo "Web App URL:     https://$(jq -r '.webAppHostName.value' deployment-outputs.json)"
echo "SQL Server:      $(jq -r '.sqlServerName.value' deployment-outputs.json)"
echo "SQL Database:    $(jq -r '.sqlDatabaseName.value' deployment-outputs.json)"
echo "UAMI Client ID:  $(jq -r '.uamiClientId.value' deployment-outputs.json)"
echo "============================================"
```

**Note on GitHub Actions vs. Local Deployment:**  
The `Deploy App Service Infrastructure` workflow is triggered manually via `workflow_dispatch`. After making Bicep changes (like in Module 5), you push your code and then manually trigger the deployment — this ensures you always deploy with the correct region and workload name. A separate `Validate App Service Infrastructure` workflow runs automatically on push and PRs to check Bicep syntax and show a what-if preview. If deploying locally, you can still complete Module 5 by re-running the deployment commands after making the Bicep change.

## Verify Resources in Azure

Once the workflow completes, verify that all resources were created successfully:

### 1. Check Azure CLI Access

Authenticate to your Azure subscription (if not already authenticated):
```bash
az login
```

### 2. List All Resources

Replace `srelabapp` with your `workloadName` if you customized it:

```bash
az resource list --resource-group rg-srelabapp -o table
```

Expected output: ~8–10 resources including the web app, App Service Plan, SQL server, SQL database, Log Analytics workspace, Application Insights, and managed identity.

### 3. Verify the Web App

```bash
az webapp show \
  --resource-group rg-srelabapp \
  --name $(az webapp list --resource-group rg-srelabapp --query "[0].name" -o tsv) \
  --query "{name:name, state:state, hostName:defaultHostName}" \
  -o table
```

Expected output:
```
Name               State    HostName
─────────────────  ───────  ─────────────────────────────────────
srelabapp-web-xxxx    Running  srelabapp-web-xxxx.azurewebsites.net
```

### 4. Verify the SQL Server

```bash
az sql server show \
  --resource-group rg-srelabapp \
  --name $(az sql server list --resource-group rg-srelabapp --query "[0].name" -o tsv) \
  --query "{name:name, fqdn:fullyQualifiedDomainName, state:state}" \
  -o table
```

Expected output:
```
Name               Fqdn                                        State
─────────────────  ──────────────────────────────────────────  ──────────
srelabapp-sql-xxxx    srelabapp-sql-xxxx.database.windows.net        Ready
```

### 5. Verify the Managed Identity

```bash
az identity show \
  --resource-group rg-srelabapp \
  --name srelabapp-id \
  --query "{name:name, clientId:clientId}" \
  -o table
```

Expected output:
```
Name       ClientId
─────────  ──────────────────────────────────────────
srelabapp-id  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Understanding the Architecture

The infrastructure implements a **managed identity** flow — the modern, secure way for App Service apps to authenticate to Azure SQL without storing connection string passwords.

### The Authentication Chain

Here's how the app will authenticate to Azure SQL in Module 2:

```
┌─────────────────────────────────────────────────────────────┐
│ App Service Web App                                         │
│                                                             │
│  App uses: Microsoft.Data.SqlClient (AD Managed Identity)  │
│  ↓                                                          │
│  Reads: AZURE_SQL_CONNECTIONSTRING (User Id=<clientId>)   │
│  ↓                                                          │
│  Requests: AAD token for Azure SQL audience               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Azure AD (Entra ID)                                         │
│                                                             │
│  Identity: User-Assigned Managed Identity {UAMI}           │
│  ↓                                                          │
│  Issues: AAD access token for Azure SQL                    │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Azure SQL                                                   │
│                                                             │
│  App presents: Bearer token (AAD access token)             │
│  ↓                                                          │
│  SQL validates token against contained user                │
│  ↓                                                          │
│  UAMI mapped to contained user with db_datareader role     │
│  ↓                                                          │
│  Authorization succeeds → data returned                    │
└─────────────────────────────────────────────────────────────┘
```

**Key components:**
- **User-Assigned Managed Identity (UAMI):** An Azure identity assigned to the web app — no passwords or certificates
- **Contained Database User:** A SQL user inside `srelabapp-db` mapped to the UAMI and granted `db_datareader`
- **AAD-Only Authentication:** The SQL server is configured for Azure AD authentication only — no SQL passwords

This chain is the foundation of what we'll break in **Module 5**. When we remove the managed-identity SQL grant in Module 5, the app will still be able to get an AAD token, but Azure SQL will reject the request — the contained user or its permissions will be absent.

## Troubleshooting

### Workflow Fails: AuthorizationFailed

**Symptom:** The GitHub Actions workflow fails with an error like:
```
AuthorizationFailed: The client '...' with object id '...' does not have authorization to perform action 'Microsoft.Web/sites/write'
```

**Cause:** Your GitHub Actions service principal doesn't have sufficient permissions on the subscription.

**Solution:**
1. Go to the Azure portal
2. Navigate to **Subscriptions** → your subscription → **Access control (IAM)**
3. Click **+ Add** → **Add role assignment**
4. Assign **Contributor** (or higher) role to the service principal used by GitHub Actions
5. Retry the workflow

---

### Workflow Fails: Region Not Supported

**Symptom:** Deployment fails with a message like `ResourceGroupNotFound` or `LocationNotAvailable`.

**Cause:** You selected a region that doesn't support all required Azure services, or the region is not enabled for SRE Agent.

**Solution:** Use one of the supported regions:
- `eastus2`
- `swedencentral`
- `australiaeast`

These regions are tested and supported by the workshop. Retry the workflow with a supported location.

---

### Workflow Fails: Quota Exceeded

**Symptom:** Deployment fails with an error like `QuotaExceeded` or `SkuNotAvailable`.

**Cause:** Your subscription has hit a resource quota or the B1 App Service tier isn't available.

**Solution:**
1. Check available SKUs: Go to Azure portal → **App Services** → **Create**
2. Request a quota increase if needed
3. Alternatively, use a free trial or a different subscription with more available quota

---

## Checkpoint: Verify Everything Works

At this point, you should have:

✅ All Azure resources created in `rg-srelabapp`  
✅ App Service Plan and web app in `Running` state  
✅ Azure SQL server (`Succeeded`) and database created  
✅ Managed identity created and assigned to the web app  
✅ SQL server configured with AAD admin  

Run this quick verification:

```bash
# List resources
az resource list --resource-group rg-srelabapp --query "[].type" -o table | wc -l
# Should show: ~8–10

# Check web app state
az webapp show --resource-group rg-srelabapp \
  --name $(az webapp list --resource-group rg-srelabapp --query "[0].name" -o tsv) \
  --query "state" -o tsv
# Should show: Running
```

If all checks pass, you're ready for **Module 2: Deploy the Application** ✨

## What's Next

The infrastructure is provisioned and ready. In Module 2, you'll:
1. Build and deploy the .NET 10 web application to the App Service
2. Run the database schema migration and grant the managed identity SQL access
3. Test the app endpoints and verify it can read the product catalog from Azure SQL

**→ [Module 2: Deploy the Application](./02-deploy-application.md)**

---

## Cost Reminder

⏱️ **Time:** Infrastructure provisioning: ~10–15 min  
💰 **Cost:** This module costs approximately **$0.125/hour** while resources are running (App Service ~$0.018/hr + SQL ~$0.007/hr + Monitoring ~$0.10/hr).

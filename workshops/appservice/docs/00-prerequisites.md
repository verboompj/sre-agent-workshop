# Module 0: Prerequisites

## Overview

Before starting the workshop, you'll need an active Azure subscription, a few command-line tools, a GitHub account, and a handful of credentials. This module walks through each requirement and shows you how to validate your setup. Estimated time: **15 minutes of reading + 10 minutes of configuration**.

## Cost Estimate

The workshop creates several Azure resources that you'll pay for by the hour. Here's the breakdown:

| Resource | Hourly Cost |
|----------|------------|
| App Service Plan (B1 Linux) | ~$0.018 |
| Azure SQL Database (Basic) | ~$0.007 |
| Log Analytics + Application Insights | ~$0.10 |
| SRE Agent | ~$0.50 |
| **Total** | **~$0.63/hr** |

**For the full workshop (3–4 hours): ~$2–5 total cost.**

> **Budget $5–10 to be safe**, especially if you experiment or leave resources running longer than expected. Azure SQL charges per DTU tier; monitoring charges based on ingestion volume. Both are minimal for a workshop scenario. Remember to run the cleanup module when done to stop incurring costs.

## Requirements

### 1. Azure Subscription

- **Minimum role:** Contributor (to create and manage resources)
- **Optional role:** Owner or User Access Administrator (if you plan to create custom role assignments)
- **Check your access:** Log in to the [Azure Portal](https://portal.azure.com) and verify you can see your subscription
- **Resource Providers**: Ensure the required resource providers are registered. Run `setup.sh` or `setup.ps1` to verify.

### 2. Supported Azure Region

The SRE Agent is available in specific regions. You **must** deploy this workshop to one of these three:

- **East US 2**
- **Sweden Central**
- **Australia East**

> When deploying infrastructure (Module 1), you'll specify your region. Pick the one closest to you or your team for lowest latency.

### 3. Network Access

Your network must allow outbound HTTPS traffic to:
- `*.azuresre.ai` (SRE Agent portal and services)
- `*.azurerm.com` (Azure API endpoints)
- `*.database.windows.net` (Azure SQL endpoints)

Most corporate networks allow this by default. If you're behind a strict firewall, contact your network team.

### 4. Required Tools

#### Azure CLI (`az`)

[Install Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) — the command-line interface for managing Azure resources.

**Quick check:**
```bash
az --version
```

#### .NET 10 SDK

[Install .NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) — required to build and publish the .NET 10 shop app locally (used in the optional local deployment path in Module 2).

**Quick check:**
```bash
dotnet --version
# Should report 10.x.x
```

#### GitHub CLI (`gh`)

[Install GitHub CLI](https://cli.github.com/) — optional but helpful for testing GitHub connectivity.

**Quick check:**
```bash
gh --version
```

### 5. GitHub Account

- You must have a GitHub account to fork the workshop repository
- Your account must have permission to fork repositories and create repositories under your personal account or organization
- [Sign up for free here](https://github.com/signup) if you don't have an account

## Step 1: Fork the Repository

The workshop repository is a template. You'll fork it to your own GitHub account, configure it with your Azure credentials, and all deployments will run against your own Azure subscription.

**Steps:**

1. Navigate to the workshop repository on GitHub: [sre-agent-workshop](https://github.com/Azure-Samples/sre-agent-workshop) (or your team's fork)
2. Click the **Fork** button in the top-right corner
3. Choose your personal account or organization as the fork destination
4. Click **Create fork**
5. Clone your fork locally:
   ```bash
   git clone https://github.com/{YOUR_USERNAME}/sre-agent-workshop.git
   cd sre-agent-workshop
   ```

Now all your work will be in your own fork, and the SRE Agent will open pull requests against *your* fork.

## Step 2: Create a Service Principal for GitHub Actions

GitHub Actions workflows in your fork need credentials to deploy infrastructure to your Azure subscription. The workflows use **OpenID Connect (OIDC) federated credentials** — no long-lived client secrets are stored in GitHub. This approach is compatible with strict Azure AD tenant policies that block client-secret-based authentication.

### Get Your Subscription and Tenant IDs

```bash
az login
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Tenant ID:       $TENANT_ID"
```

Keep this terminal open — you'll use these values in the next steps.

### Create an App Registration and Service Principal

```bash
# Create the app registration
export APP_ID=$(az ad app create --display-name "sre-workshop-sp" --query appId -o tsv)

# Create the service principal for the app
az ad sp create --id $APP_ID

# Assign Contributor access to your subscription
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID

echo "App (Client) ID: $APP_ID"
```

> **Note:** This app registration also becomes the Azure SQL AAD administrator automatically during infrastructure deployment. This allows the app-deployment workflow to run schema migrations and managed-identity grants via `sqlcmd` without additional configuration.

### Add a Federated Credential for GitHub Actions

Replace `{YOUR_USERNAME}` with your GitHub username:

```bash
GITHUB_USER="{YOUR_USERNAME}"

az ad app federated-credential create \
  --id $APP_ID \
  --parameters "{
    \"name\": \"sre-workshop-gh-actions\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_USER}/sre-agent-workshop:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

> **Note:** The federated credential binds GitHub's OIDC token (issued for your `main` branch) to your app registration. No client secret is created or stored — the workflows authenticate via the short-lived OIDC token GitHub provides at runtime.
>
> Always delete the app registration when done with the workshop (see Module 7).

## Step 3: Configure GitHub Actions Secrets

Your fork needs three secrets to authenticate via OIDC. These values are not sensitive credentials (no passwords or keys), but storing them as GitHub secrets avoids exposing your Azure tenant and subscription IDs in workflow logs.

**Steps:**

1. Go to your fork on GitHub (https://github.com/{YOUR_USERNAME}/sre-agent-workshop)
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add these three secrets:

| Secret Name | Value | How to get it |
|-------------|-------|--------------|
| `AZURE_CLIENT_ID` | The app registration's client (application) ID | The `$APP_ID` value from the step above |
| `AZURE_TENANT_ID` | Your Azure AD tenant ID | The `$TENANT_ID` value from the step above |
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID | The `$SUBSCRIPTION_ID` value from the step above |

> **Security note:** GitHub encrypts these secrets in transit and at rest. They're only exposed to workflows running in your repository and cannot be read back via the GitHub UI.

## Step 4: Configure Repository Variables (Optional)

Repository variables provide default values for your workflows and the validation what-if preview. While deploy workflows always let you pick the region and workload name explicitly, setting these variables means the `Validate App Service Infrastructure` workflow (which runs on push and PRs) can show an accurate what-if preview against your actual environment.

**Steps:**

1. Go to your fork on GitHub (https://github.com/{YOUR_USERNAME}/sre-agent-workshop)
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Switch to the **Variables** tab
4. Click **New repository variable** and add these variables:

| Variable Name | Value | Description |
|---------------|-------|-------------|
| `WORKLOAD_NAME` | Your chosen workload name (e.g., `srelabapp`) | Used in resource naming — should match what you used in Module 1 |
| `AZURE_LOCATION` | Your chosen Azure region (e.g., `eastus2`) | Should match the region used in Module 1 |

> **Why this matters:** The `Validate App Service Infrastructure` workflow runs automatically when you push Bicep changes or open a PR. It validates Bicep syntax and shows a what-if preview of what the deployment would change. Without these variables, the what-if preview targets the default `srelabapp` / `eastus2`, which may not match your actual deployment.

## Step 5: Verify Your Setup

Run these commands to confirm everything is ready:

```bash
# Verify Azure CLI and authentication
az login
az account show

# Verify .NET 10 SDK
dotnet --version

# Verify GitHub CLI (optional)
gh auth status

# Verify your fork is cloned
cd sre-agent-workshop
git remote -v  # should show your fork as origin
```

**Expected output:**
- `az account show` displays your subscription name and ID
- `dotnet --version` reports `10.x.x`
- `gh auth status` shows "Logged in to github.com..." (if installed)
- `git remote -v` shows your fork URL for both fetch and push

## Checklist

Before moving to Module 1, verify:

- [ ] Azure subscription with Contributor access
- [ ] Azure region selected (East US 2, Sweden Central, or Australia East)
- [ ] Network can reach `*.azuresre.ai` and `*.database.windows.net`
- [ ] Azure CLI installed and logged in (`az account show` works)
- [ ] .NET 10 SDK installed (`dotnet --version` shows `10.x.x`)
- [ ] GitHub account created
- [ ] Repository forked to your account
- [ ] App registration and service principal created
- [ ] Federated credential added to the app registration
- [ ] `AZURE_CLIENT_ID` secret added to your fork
- [ ] `AZURE_TENANT_ID` secret added to your fork
- [ ] `AZURE_SUBSCRIPTION_ID` secret added to your fork
- [ ] `WORKLOAD_NAME` variable added to your fork (if using a custom name)
- [ ] `AZURE_LOCATION` variable added to your fork (if using a non-default region)
- [ ] Secrets and variables are visible in Settings → Secrets and variables → Actions

## Cost Reminder

You're about to provision real Azure resources that incur hourly charges. The workshop should take **3–4 hours total**, so budget for **~$5–10**. When you're done, **run the cleanup steps in Module 7** to delete all resources and stop incurring charges.

## Next Step

→ **[Module 1: Deploy Infrastructure](./01-deploy-infrastructure.md)**

Ready? Proceed to Module 1 to deploy the App Service, Azure SQL, monitoring, and managed identity resources using Bicep.

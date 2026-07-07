# VM Module 0: Prerequisites

## Required

- Azure subscription with Contributor access
- GitHub fork of this repository
- Azure CLI (`az`)
- Access to supported regions: `eastus2`, `swedencentral`, or `australiaeast`
- Repository secrets:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
  - `VM_ADMIN_PASSWORD`
- Azure CLI supports `az network bastion tunnel` (install/update the `bastion` extension if prompted)

## Configure OIDC Credentials

The workflows authenticate to Azure using OpenID Connect (OIDC) federated credentials — no client secrets required.

```bash
az login
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)

# Create app registration and service principal
export APP_ID=$(az ad app create --display-name "sre-workshop-sp" --query appId -o tsv)
az ad sp create --id $APP_ID
az role assignment create --assignee $APP_ID --role Contributor --scope /subscriptions/$SUBSCRIPTION_ID

# Add federated credential (replace {YOUR_USERNAME})
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

Add these secrets to your fork (**Settings → Secrets and variables → Actions**):

| Secret Name | Value |
|-------------|-------|
| `AZURE_CLIENT_ID` | `$APP_ID` from above |
| `AZURE_TENANT_ID` | `$TENANT_ID` from above |
| `AZURE_SUBSCRIPTION_ID` | `$SUBSCRIPTION_ID` from above |
| `VM_ADMIN_PASSWORD` | A strong password for the Windows VM admin account |

## Validate locally

```powershell
.\workshops\vm\scripts\setup.ps1 -Location eastus2
```


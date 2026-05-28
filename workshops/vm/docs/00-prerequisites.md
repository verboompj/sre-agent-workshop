# VM Module 0: Prerequisites

## Required

- Azure subscription with Contributor access
- GitHub fork of this repository
- Azure CLI (`az`)
- Access to supported regions: `eastus2`, `swedencentral`, or `australiaeast`
- Repository secrets:
  - `AZURE_CREDENTIALS`
  - `VM_ADMIN_PASSWORD`
- Azure CLI supports `az network bastion tunnel` (install/update the `bastion` extension if prompted)

## Validate locally

```powershell
.\workshops\vm\scripts\setup.ps1 -Location eastus2
```


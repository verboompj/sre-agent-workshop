@description('Azure region for identity resources')
param location string

@description('Base name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

// ──────────────────────────────────────────────
// User-Assigned Managed Identity
// Assigned to the App Service and granted a least-privilege
// contained user in Azure SQL (the grant runs in CI, not Bicep).
// ──────────────────────────────────────────────
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${workloadName}-id'
  location: location
  tags: tags
}

// ── Outputs ──────────────────────────────────
@description('User-Assigned Managed Identity client ID')
output uamiClientId string = uami.properties.clientId

@description('User-Assigned Managed Identity principal ID')
output uamiPrincipalId string = uami.properties.principalId

@description('User-Assigned Managed Identity resource ID')
output uamiId string = uami.id

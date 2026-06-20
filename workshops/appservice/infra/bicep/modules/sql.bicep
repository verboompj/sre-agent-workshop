@description('Azure region for SQL resources')
param location string

@description('Base name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Deterministic suffix for the globally-unique SQL server name')
param uniqueSuffix string

@description('Object ID of the AAD principal to set as SQL admin (the deploying service principal)')
param sqlAadAdminObjectId string

@description('Login display name for the AAD admin')
param sqlAadAdminLogin string = 'sql-admin'

// ──────────────────────────────────────────────
// SQL logical server — AAD-only authentication
// ──────────────────────────────────────────────
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: '${workloadName}-sql-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Application'
      login: sqlAadAdminLogin
      sid: sqlAadAdminObjectId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// ──────────────────────────────────────────────
// Database — Basic tier (5 DTU)
// ──────────────────────────────────────────────
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: '${workloadName}-db'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}

// ──────────────────────────────────────────────
// Firewall — allow Azure services (App Service outbound)
// The 0.0.0.0/0.0.0.0 rule is the special "Allow Azure services" entry.
// ──────────────────────────────────────────────
resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ── Outputs ──────────────────────────────────
@description('SQL logical server name')
output sqlServerName string = sqlServer.name

@description('SQL server fully-qualified domain name')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL database name')
output sqlDatabaseName string = sqlDatabase.name

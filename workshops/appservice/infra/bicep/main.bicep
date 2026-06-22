// ──────────────────────────────────────────────────────────────
// Azure SRE Agent Workshop — App Service Track — Main Orchestrator
// Composes: Monitoring → Identity → SQL → App Service → [Alerts seam]
// ──────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Azure region for all resources')
@allowed([
  'eastus2'
  'swedencentral'
  'australiaeast'
])
param location string = 'eastus2'

@description('Base workload name used in resource naming ({workloadName}-{type})')
param workloadName string = 'srelabapp'

@description('Resource tags applied to every resource')
param tags object = {
  workshop: 'sre-agent'
  environment: 'demo'
}

@description('Object ID of the AAD principal set as SQL admin (the deploying service principal)')
param sqlAadAdminObjectId string

// Deterministic 4-char suffix for globally unique resource names (SQL server, web app)
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)

// ──────────────────────────────────────────────
// 1. Monitoring (Log Analytics + workspace-based App Insights)
// ──────────────────────────────────────────────
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
  }
}

// ──────────────────────────────────────────────
// 2. Identity (UAMI assigned to the web app)
// ──────────────────────────────────────────────
module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
  }
}

// ──────────────────────────────────────────────
// 3. Azure SQL (server + database + firewall)
// ──────────────────────────────────────────────
module sql 'modules/sql.bicep' = {
  name: 'sql'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    uniqueSuffix: uniqueSuffix
    sqlAadAdminObjectId: sqlAadAdminObjectId
  }
}

// ──────────────────────────────────────────────
// 4. App Service (plan + web app + diagnostics)
// ──────────────────────────────────────────────
module appservice 'modules/appservice.bicep' = {
  name: 'appservice'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    uniqueSuffix: uniqueSuffix
    uamiId: identity.outputs.uamiId
    uamiClientId: identity.outputs.uamiClientId
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    sqlDatabaseName: sql.outputs.sqlDatabaseName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    logAnalyticsId: monitoring.outputs.logAnalyticsId
  }
}

// ──────────────────────────────────────────────
// 5. SCENARIO ALERTS — generated aggregator wired to the Log Analytics scope
// ──────────────────────────────────────────────
module scenarioAlerts 'modules/scenario-alerts.bicep' = {
  name: 'scenario-alerts'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    logAnalyticsResourceId: monitoring.outputs.logAnalyticsId
  }
}

// ── Outputs ──────────────────────────────────
@description('Web App name')
output webAppName string = appservice.outputs.webAppName

@description('Web App default host name')
output webAppHostName string = appservice.outputs.webAppHostName

@description('SQL logical server name')
output sqlServerName string = sql.outputs.sqlServerName

@description('SQL database name')
output sqlDatabaseName string = sql.outputs.sqlDatabaseName

@description('Log Analytics workspace resource ID')
output logAnalyticsId string = monitoring.outputs.logAnalyticsId

@description('User-Assigned Managed Identity client ID')
output uamiClientId string = identity.outputs.uamiClientId

@description('User-Assigned Managed Identity principal ID')
output uamiPrincipalId string = identity.outputs.uamiPrincipalId

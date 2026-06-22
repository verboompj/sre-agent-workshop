@description('Azure region for the App Service resources')
param location string

@description('Base name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Deterministic suffix for the globally-unique web app name')
param uniqueSuffix string

@description('Resource ID of the user-assigned managed identity to assign')
param uamiId string

@description('Client ID of the user-assigned managed identity (for the SQL connection string)')
param uamiClientId string

@description('SQL server fully-qualified domain name')
param sqlServerFqdn string

@description('SQL database name')
param sqlDatabaseName string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Log Analytics workspace resource ID for diagnostic settings')
param logAnalyticsId string

var sqlConnectionString = 'Server=tcp:${sqlServerFqdn},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;User Id=${uamiClientId};Encrypt=True;TrustServerCertificate=False'

var appSettingsArray = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  {
    name: 'AZURE_SQL_CONNECTIONSTRING'
    value: sqlConnectionString
  }
  {
    name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
    value: 'false'
  }
]

// ──────────────────────────────────────────────
// App Service Plan (S1 Linux — Standard tier required for deployment slots)
// ──────────────────────────────────────────────
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${workloadName}-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  properties: {
    reserved: true
  }
}

// ──────────────────────────────────────────────
// Web App (.NET 10, passwordless SQL via UAMI)
// ──────────────────────────────────────────────
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${workloadName}-web-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      healthCheckPath: '/health'
      appSettings: appSettingsArray
    }
  }
}

// ──────────────────────────────────────────────
// Staging deployment slot (canary target — clones production config)
// ──────────────────────────────────────────────
resource stagingSlot 'Microsoft.Web/sites/slots@2023-12-01' = {
  parent: webApp
  name: 'staging'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      healthCheckPath: '/health'
      appSettings: appSettingsArray
    }
  }
}

// ──────────────────────────────────────────────
// Diagnostic settings → Log Analytics workspace
// ──────────────────────────────────────────────
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-law'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────
@description('Web App name')
output webAppName string = webApp.name

@description('Web App default host name')
output webAppHostName string = webApp.properties.defaultHostName

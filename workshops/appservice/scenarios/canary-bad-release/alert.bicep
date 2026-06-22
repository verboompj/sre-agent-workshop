@description('Azure region for the alert')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (Log Analytics workspace)')
param scopeResourceId string

resource canary5xxAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-canary-5xx'
  location: location
  tags: tags
  properties: {
    displayName: 'Canary 5xx on /products'
    description: 'Fires when /products requests fail (5xx) — typically a bad release on the staging canary slot.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [scopeResourceId]
    criteria: {
      allOf: [
        {
          query: '''
            AppRequests
            | where TimeGenerated > ago(10m)
            | where Url contains "/products"
            | where Success == false or toint(ResultCode) >= 500
            | summarize Failures = count()
          '''
          timeAggregation: 'Total'
          metricMeasureColumn: 'Failures'
          operator: 'GreaterThan'
          threshold: 3
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}

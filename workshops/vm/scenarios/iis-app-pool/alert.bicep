@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (Log Analytics workspace)')
param scopeResourceId string

resource iisFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-vm-iis-app-pool-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'IIS App Pool Failure'
    description: 'Alerts when IIS service/app pool state transitions indicate stopped workload.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      scopeResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source has "IIS" or EventLog == "System"
            | where RenderedDescription has "stopped" or RenderedDescription has "terminated"
            | summarize FailureCount=count() by Computer, bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
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

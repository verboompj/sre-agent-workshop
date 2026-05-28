@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Log Analytics workspace customer ID (GUID)')
param logAnalyticsWorkspaceId string

@description('Log Analytics workspace resource ID')
param logAnalyticsResourceId string

// ──────────────────────────────────────────────
// Alert: VM disk free space < 10% on C:
//   Triggers Scenario 1 (Disk Full) investigation
// ──────────────────────────────────────────────
resource diskPressureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-vm-disk-pressure'
  location: location
  tags: tags
  properties: {
    displayName: 'VM Disk Free Space Critical'
    description: 'Alerts when C: free space drops below 10 percent on workshop VMs.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "LogicalDisk" and CounterName == "% Free Space" and InstanceName == "C:"
            | summarize FreeSpace=min(CounterValue) by Computer, bin(TimeGenerated, 5m)
          '''
          metricMeasureColumn: 'FreeSpace'
          timeAggregation: 'Average'
          operator: 'LessThan'
          threshold: 10
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

// ──────────────────────────────────────────────
// Alert: IIS / Windows service stop events
//   Triggers Scenario 2 (App Pool Failure) investigation
// ──────────────────────────────────────────────
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
      logAnalyticsResourceId
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

// ──────────────────────────────────────────────
// Alert: Sustained CPU > 85%
//   Triggers Scenario 3 (CPU Runaway) investigation
// ──────────────────────────────────────────────
resource cpuRunawayAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-vm-cpu-runaway'
  location: location
  tags: tags
  properties: {
    displayName: 'VM CPU Runaway'
    description: 'Alerts when CPU exceeds 85 percent on workshop VMs.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
            | summarize AvgCpu=avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
          '''
          metricMeasureColumn: 'AvgCpu'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 85
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

// ── Outputs ──────────────────────────────────
@description('Log Analytics workspace ID (GUID) — pass-through for convenience')
output workspaceId string = logAnalyticsWorkspaceId


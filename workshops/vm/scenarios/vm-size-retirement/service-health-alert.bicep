// ──────────────────────────────────────────────────────────────
// PRODUCTION REFERENCE — NOT deployed by the workshop.
// Shows how, in a real environment, an Azure Service Health "service retirement"
// advisory reaches the SRE Agent: a subscription-scoped Activity Log alert on
// category=ServiceHealth routes matching events to an Action Group.
//
// Azure Service Health events cannot be injected on demand, so this scenario
// SIMULATES the advisory instead (see inject.sh / service-health-advisory.json).
// This file is intentionally NOT named alert.bicep and is NOT wired into the
// scenario aggregator. Build it standalone with:
//   az bicep build --file service-health-alert.bicep --stdout
// ──────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@description('Resource tags')
param tags object = {}

@description('Subscription scope the Service Health alert watches')
param alertScope string = subscription().id

@description('Name for the Action Group that routes Service Health events to the SRE Agent')
param actionGroupName string = 'sre-agent-servicehealth-ag'

@description('Short name (<=12 chars) shown in notifications')
param actionGroupShortName string = 'sreagent'

@description('Webhook URI the SRE Agent (or its incident intake) exposes for Service Health events')
param sreAgentWebhookUri string

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    webhookReceivers: [
      {
        name: 'sre-agent'
        serviceUri: sreAgentWebhookUri
        useCommonAlertSchema: true
      }
    ]
  }
}

resource serviceHealthRetirementAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'service-health-vm-size-retirement'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      alertScope
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'ActionRequired'
        }
        {
          field: 'properties.impactedServices[*].ServiceName'
          containsAny: [
            'Virtual Machines'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

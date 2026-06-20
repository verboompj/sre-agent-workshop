using './main.bicep'

param location = 'eastus2'
param workloadName = 'srelab'
param tags = {
  workshop: 'sre-agent'
  environment: 'demo'
}
// Overridden by the deploy workflow with the deploying service principal's object ID.
param sqlAadAdminObjectId = ''

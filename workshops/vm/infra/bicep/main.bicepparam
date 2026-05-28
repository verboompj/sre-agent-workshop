using './main.bicep'

param location = 'eastus2'
param workloadName = 'srelabvm'
param adminUsername = 'azureuser'
param adminPassword = ''
param tags = {
  workshop: 'sre-agent'
  environment: 'demo'
  track: 'vm'
}


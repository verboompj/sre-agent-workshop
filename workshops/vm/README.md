# VM Workshop Track 🖥️

**AI-powered operational intelligence for migrated enterprise workloads.**

This track extends the workshop with realistic VM-first operations scenarios:

- Windows Server virtual machines
- IIS-hosted web workload
- Azure Monitor + Log Analytics + VM Insights signals
- Bastion-first access (no public VM endpoints required)
- Investigation traces with explicit reasoning stages
- Approval-gated remediation actions
- Postmortem generation

## What you deploy

- 2 Windows Server VMs with IIS configured
- B-series VM family (`Standard_B2s`) for lower workshop runtime cost
- Daily VM auto-shutdown schedules (UTC 19:00) enabled by default
- Virtual network + NSG
- Azure Bastion host for secure operator access
- Log Analytics + Application Insights
- Managed identity + RBAC for investigation tooling
- Scheduled query alerts for disk pressure, IIS failures, and CPU spikes

## Workshop modules

- [00. Prerequisites](./docs/00-prerequisites.md)
- [01. Deploy Infrastructure](./docs/01-deploy-infrastructure.md)
- [02. Configure Incident Response](./docs/02-configure-incident-response.md)
- [03. Scenario 1: Disk Full](./docs/03-scenario-disk-full.md)
- [04. Scenario 2: IIS App Pool Failure](./docs/04-scenario-iis-app-pool.md)
- [05. Scenario 3: CPU Runaway](./docs/05-scenario-cpu-runaway.md)
- [06. Watch Agent Workflow](./docs/06-watch-agent-workflow.md)
- [07. Cleanup](./docs/07-cleanup.md)


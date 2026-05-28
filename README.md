# Azure SRE Agent Workshop 🔧

**Deploy infrastructure, break it on purpose, and watch AI fix it.**

A hands-on workshop that teaches operations teams how the Azure SRE Agent detects, diagnoses, and remediates infrastructure faults across **Kubernetes and VM-based enterprise workloads**. You'll provision real infrastructure, deploy an application, introduce realistic failures, and observe the SRE Agent investigate and propose fixes via GitHub.

---

## 🎯 What You'll Learn

- **Deploy AKS infrastructure** using Bicep Infrastructure-as-Code and GitHub Actions
- **Deploy a web application** to AKS with Azure workload identity authentication
- **Onboard and configure** the Azure SRE Agent with your GitHub repo and Azure resources
- **Introduce a realistic fault** (removed role assignment) that breaks application access to CosmosDB
- **Watch the SRE Agent** detect the failure, trace it through logs/commits, and open a PR to fix it
- **Run VM migration scenarios** on Windows Server + IIS with approval-gated remediation workflows

By the end of the workshop, you'll understand how modern AI-assisted incident response accelerates MTTR and improves reliability at scale.

---

## 🏗️ Architecture

The workshop deploys a complete infrastructure environment and simulates a real incident:

```
GitHub Repo (Your Fork)
  ├─ Bicep Code ──[GitHub Actions]──> Azure Resources
  │                                      ├─ AKS Cluster (2 nodes, workload identity enabled)
  │                                      ├─ CosmosDB (serverless, NoSQL API)
  │                                      ├─ Log Analytics + Application Insights
  │                                      └─ User-Assigned Managed Identity + RBAC
  │
  ├─ Kubernetes Manifests ──> App Pods in AKS
  │                              └─ Node.js Web App
  │                                   └─ Uses DefaultAzureCredential + Workload Identity
  │                                       └─ Accesses CosmosDB via RBAC Role
  │
  └─ SRE Agent (sre.azure.com)
       ├─ Connects: GitHub Repo + Azure Resources
       ├─ Monitors: Azure Monitor Alert
       ├─ Traces: Deployment → Commit → Code
       └─ Acts: Diagnoses → Opens PR with Fix
```

### Authentication Flow

The app authenticates to CosmosDB via **Workload Identity**:

```
1. Pod requests token from OIDC provider
   └─> K8s ServiceAccount (with annotation)
2. OIDC issues token for managed identity
   └─> User-Assigned Managed Identity
3. Token authenticated against CosmosDB
   └─> Role Assignment grants data-plane access
4. App reads data successfully
   └─> DefaultAzureCredential handles all of this
```

When the role assignment is removed, step 3 fails → app returns 500 → SRE Agent responds.

---

## 🧭 Workshop Tracks

This repository now supports two aligned workshop tracks:

| Track | Focus | Entry Point |
|--------|----------|-----------|
| **AKS / Cloud-Native** | Kubernetes workload identity, CosmosDB RBAC fault injection | This README + [`docs/`](docs/) |
| **VM / Enterprise Migration** | Windows Server, IIS, Bastion-first access, VM observability, approval-gated remediation | [`workshops/vm/README.md`](workshops/vm/README.md) |

---

## 📋 AKS Workshop Modules

Each module takes 20–30 minutes and builds on the previous one. **Total workshop time: ~3–4 hours**.

| Module | Duration | What You Do |
|--------|----------|-----------|
| **[0. Prerequisites](docs/00-prerequisites.md)** | Pre-work | Set up Azure subscription, tools, GitHub fork, and secrets |
| **[1. Deploy Infrastructure](docs/01-deploy-infrastructure.md)** | ~30 min | Provision AKS, CosmosDB, monitoring, and managed identity via Bicep |
| **[2. Deploy Application](docs/02-deploy-application.md)** | ~30 min | Deploy the web app to AKS with workload identity |
| **[3. Onboard SRE Agent](docs/03-onboard-sre-agent.md)** | ~30 min | Create SRE Agent, connect GitHub repo, grant Azure access |
| **[4. Configure Incident Response](docs/04-configure-incident-response.md)** | ~20 min | Connect Azure Monitor alerts and set autonomy level |
| **[5. Break It](docs/05-break-it.md)** | ~20 min | Intentionally remove a role assignment—introduce the fault |
| **[6. Watch SRE Agent](docs/06-watch-sre-agent.md)** | ~30 min | Observe SRE Agent investigate and open a fix PR |
| **[7. Cleanup](docs/07-cleanup.md)** | ~10 min | Delete all resources and wrap up |

---

## 💰 Cost Estimate

This workshop runs on Azure resources that incur real costs. The following estimate assumes the full ~3–4 hour workshop:

| Resource | Cost/Hour | Notes |
|----------|-----------|-------|
| AKS (2× Standard_DS2_v2 nodes) | ~$0.25 | Largest cost; note: nodes run during entire workshop |
| CosmosDB (serverless) | ~$0.05 | Minimal RUs for a workshop scenario |
| Log Analytics + App Insights | ~$0.10 | Standard monitoring pricing |
| SRE Agent | ~$0.50 | Depends on model provider and investigation volume |
| **Total** | **~$1.00/hr** | ~$4–6 for full workshop |

**Budget recommendation: Set aside $10 to be safe.** Remember to run **Module 7 (Cleanup)** when done—resources still incur costs when left running.

---

## 🚀 Quick Start

### Prerequisites
- Azure subscription with **Contributor** access
- Azure CLI and `kubectl` installed
- GitHub account (you'll fork this repo)
- Supported region: **East US 2**, **Sweden Central**, or **Australia East**
- Outbound network access to `*.azuresre.ai` (SRE Agent access)

### Clone & Begin

```bash
# 1. Fork this repository on GitHub
#    (Go to https://github.com/Azure/sre-agent-workshop and click "Fork")

# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/sre-agent-workshop.git
cd sre-agent-workshop

# 3. Verify setup (optional)
./scripts/setup.sh

# 4. Start with Module 0
cat docs/00-prerequisites.md
```

Then follow each module in order. Each one builds on the previous.

---

## 📁 Repository Structure

```
sre-agent-workshop/
├── README.md                              # You are here
├── workshops/
│   ├── aks/                               # AKS track entry (compatibility-first)
│   └── vm/                                # VM track (infra, scripts, docs, tooling)
├── docs/
│   ├── 00-prerequisites.md                # Module 0: Setup & pre-work
│   ├── 01-deploy-infrastructure.md        # Module 1: Provision Azure
│   ├── 02-deploy-application.md           # Module 2: Deploy app
│   ├── 03-onboard-sre-agent.md            # Module 3: Create SRE Agent
│   ├── 04-configure-incident-response.md  # Module 4: Alert response
│   ├── 05-break-it.md                     # Module 5: Introduce fault
│   ├── 06-watch-sre-agent.md              # Module 6: Observe remediation
│   └── 07-cleanup.md                      # Module 7: Clean up
│
├── infra/bicep/
│   ├── main.bicep                         # Bicep orchestrator template
│   ├── main.bicepparam                    # Default parameters
│   └── modules/
│       ├── aks.bicep                      # AKS cluster definition
│       ├── cosmosdb.bicep                 # CosmosDB account + database
│       ├── monitoring.bicep               # Log Analytics + App Insights
│       └── identity.bicep                 # Managed identity + role assignments
│
├── src/app/
│   ├── Dockerfile                         # Container image definition
│   ├── package.json                       # Node.js dependencies
│   ├── server.js                          # Express app with 3 endpoints
│   └── package-lock.json
│
├── k8s/
│   ├── namespace.yaml                     # Kubernetes namespace
│   ├── service-account.yaml               # ServiceAccount for workload identity
│   ├── deployment.yaml                    # App deployment
│   └── service.yaml                       # LoadBalancer service
│
├── .github/workflows/
│   ├── publish-image.yml                  # Build & publish container to ghcr.io
│   ├── deploy-infra.yml                   # Deploy Bicep to Azure
│   ├── deploy-vm-infra.yml                # Deploy VM workshop infra
│   ├── deploy-app.yml                     # Deploy K8s manifests
│   └── validate-vm-infra.yml              # Validate VM workshop Bicep
│
└── scripts/
    ├── setup.sh                           # Pre-workshop validation
    └── cleanup.sh                         # Resource deletion helper
```

---

## ⚠️ Important Notes

### Regions
The Azure SRE Agent is available in **East US 2**, **Sweden Central**, and **Australia East**. Choose one of these when provisioning your workshop environment.

### Network Requirements
- Your network must allow outbound HTTPS to `*.azuresre.ai`
- If behind a corporate proxy, ensure it doesn't block this domain

### AKS Accessibility
The AKS cluster must be public (not private). The SRE Agent needs network access to query cluster logs and metrics.

### Cleanup is Critical
Resources like AKS and CosmosDB incur hourly costs even if idle. **Always run Module 7 (Cleanup)** to delete resources when done. A forgotten cluster can cost $20–30 overnight.

### Production Use
This workshop is designed for learning. Do not use these patterns (especially Autonomous autonomy level) in production without additional controls, approval gates, and testing.

---

## 📚 Resources & References

- **[Azure SRE Agent Docs](https://sre.azure.com/docs/overview)** — Full SRE Agent documentation
- **[Azure SRE Agent Portal](https://sre.azure.com)** — Where you create and monitor agents
- **[AKS Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview)** — Deep dive into workload identity in Kubernetes
- **[Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)** — Learn Infrastructure-as-Code with Bicep
- **[Azure Monitor Alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview)** — Alert rules and incident response

---

## 🤝 Contributing

Found an issue or want to improve the workshop? Contributions welcome!

- **Report issues:** Open a GitHub issue with details (module, error, screenshots)
- **Suggest improvements:** Fork, make changes, and open a pull request
- **Ask questions:** Discussion welcome in issue threads

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

---

**Ready to begin?** Start with [Module 0: Prerequisites](docs/00-prerequisites.md) →

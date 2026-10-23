# Danny — History

## Core Context

- **Project:** A hands-on workshop introducing Azure SRE Agent capabilities within AKS through guided scenarios and Bicep infrastructure
- **Role:** Lead
- **Joined:** 2026-04-12T08:49:21.223Z

## Learnings

<!-- Append learnings below -->

### 2026-04-12 — Final Architecture Review

**Reviewed:** All Bicep modules, server.js, K8s manifests, GitHub Actions workflows, all 8 module docs, scripts, README.

**Critical findings:**
1. CosmosDB created as MongoDB API but app uses `@azure/cosmos` (SQL SDK) and `sqlRoleAssignments`. Fundamental API mismatch — nothing will work. Fix: switch to NoSQL (Core) API (`kind: 'GlobalDocumentDB'`).
2. Container image published to `ghcr.io/{owner}/sre-agent-workshop/app:latest` but deployment.yaml references `ghcr.io/{owner}/sre-agent-workshop:latest` — missing `/app` segment. Pods will ImagePullBackOff.
3. Only alert deployed (container restarts) won't fire for the fault scenario because health probes still pass. Need an HTTP 500 or auth-failure log alert.

**Patterns noted:**
- Cross-layer consistency (Bicep naming → workflow queries → K8s manifests) is excellent — only the two bugs above break it.
- The health-check-doesn't-check-DB design is a strong narrative choice that makes the fault scenario realistic.
- The federated credential ↔ K8s ServiceAccount binding is wired correctly end to end.
- Documentation quality is high — troubleshooting sections are particularly thorough.

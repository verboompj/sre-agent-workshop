# Basher — History

## Core Context

- **Project:** A hands-on workshop introducing Azure SRE Agent capabilities within AKS through guided scenarios and Bicep infrastructure
- **Role:** Tech Writer
- **Joined:** 2026-04-12T08:49:21.228Z

## Learnings

### Session: Workshop Guide Authoring (2026-04-12)

**Completed work:**
- `docs/00-prerequisites.md` — Module 0 Prerequisites guide with cost estimate, tool setup, fork/secrets configuration, and verification checklist
- `docs/07-cleanup.md` — Module 7 Cleanup guide with resource deletion, secret removal, verification, and accomplishment recap
- `docs/03-onboard-sre-agent.md` — Module 3 guide covering SRE Agent creation, code repository connection, Azure resource access, and team onboarding
- `docs/04-configure-incident-response.md` — Module 4 guide covering Azure Monitor connection, incident response plan setup, and autonomy levels

**Key decisions:**
- Prerequisites structured around participant fork model: each attendee forks the repo and configures Azure secrets for their own subscription
- Emphasized the $1/hr cost estimate upfront and throughout to set expectations
- Cleanup guide follows deletion order: Azure resources → SRE Agent → GitHub secrets/SP → optional fork deletion
- Added "What You Accomplished" section to Module 7 to reinforce learning outcomes and celebrate the full incident response workflow
- Module 3 emphasizes SRE Agent's correlation capabilities across logs/metrics/code/commits — critical for participants to understand how agent will diagnose the fault introduced in Module 5
- Module 4 clearly contrasts Review vs. Autonomous autonomy levels with production guidance, helps participants understand the workshop environment is safe for full automation
- Both guides use consistent tone: direct, step-by-step, with clear commands and expected outputs

**Key file paths:**
- `docs/00-prerequisites.md` — Entry point for new attendees; establishes cost awareness and setup requirements
- `docs/03-onboard-sre-agent.md` — Module 3: Agent creation and knowledge building (30 min)
- `docs/04-configure-incident-response.md` — Module 4: Alert response automation setup (20 min)
- `docs/07-cleanup.md` — Final module; critical for cost management and cleanup verification
- `.squad/agents/basher/history.md` — This file (team knowledge)

### Module 6: Watch SRE Agent Work (2026-04-12)

**Completed work:**
- `docs/06-watch-sre-agent.md` — Module 6 guide covering the climactic investigation and remediation phase (~30 min)

**Key narrative elements:**
- Structured the SRE Agent investigation into 6 sequential phases: Alert Acknowledgment → Log/Metric Analysis → Deployment Correlation → Code Analysis → Root Cause ID → Remediation
- Each phase specifies what attendees will see: log excerpts, timeline correlations, Bicep diffs, PR description structure
- Full fault lifecycle traced from commit through recovery with realistic timestamps (~10 min total)
- Verification steps include concrete curl commands to test `/health` and `/items` endpoints post-recovery
- "Discussion Points" section encourages group reflection on MTTR improvements (5–10 min vs 30–60+ min), deployment tracing value, and agent learning
- Comparison table (traditional ops vs. SRE Agent) emphasizes the automation gains across incident lifecycle phases

**Key design decisions:**
- Structured investigation with phase timelines to manage attendee expectations and build narrative tension
- Included realistic error messages (403 Forbidden, 100% error rate) to make the scenario tangible
- Provided PR description template so attendees know what structured diagnosis looks like
- Emphasized that agent learns from incidents and recognizes patterns faster on repeat
- Balanced technical precision with accessibility for ops audiences new to AI-assisted incident response
- Used callouts, emojis, and strategic formatting to maintain engagement through dense technical content

**Key file paths:**
- `docs/06-watch-sre-agent.md` — Module 6: Watch SRE Agent investigation and PR-based remediation (30 min)
- `docs/06-watch-sre-agent.md` → "What Just Happened — The Full Flow" section — Complete timeline from Module 5 fault introduction through Module 6 resolution

### Modules 2 and 5: Deploy Application & Break It (2026-04-12)

**Completed work:**
- `docs/02-deploy-application.md` — Module 2: Deploy web app to AKS via GitHub Actions (~30 min)
- `docs/05-break-it.md` — Module 5: Introduce infrastructure fault by removing Bicep role assignment (~20 min)

**Module 2 structure and key content:**
- Overview of workload identity authentication chain: Pod → ServiceAccount → Federated Credential → UAMI → CosmosDB RBAC → Database Access
- Three app endpoints explained: `/` (landing page with status), `/health` (intentionally independent of DB), `/items` (reads from CosmosDB via workload identity)
- GitHub Actions workflow instructions: parameter (workloadName must match Module 1), estimated runtime (3–5 min)
- Verification steps: kubectl commands for pods/services, external IP wait time, curl tests with expected outputs
- Troubleshooting section: common failure modes (Pending, ImagePullBackOff, 500 errors, DefaultAzureCredential failures) with diagnosis commands
- Checkpoint description explains the full identity chain that participants verify when `/items` returns 200

**Module 5 structure and key content:**
- Narrative framing: realistic scenario of engineer removing "unused" role assignment during cleanup — builds tension
- "Verify Current State" section confirms app works before intentional break
- Exact change instructions: identifies the Bicep resource by its workshop comment ("WORKSHOP: This role assignment is critical..."), provides full code block to remove
- Three-step deployment: git add/commit/push, workflow trigger, confirmation via Actions tab
- "Watch It Break" demonstrates the failure pattern: `/health` returns 200 (deceiving), `/items` returns 500 with authorization error
- "Under the Hood" section traces the auth chain breakdown: token accepted but RBAC role missing, CosmosDB rejects request, alerts fire
- Narrative tension maintained with story callouts and emphasis on NOT fixing it manually — sets up Module 6

**Key design decisions:**
- Module 2 emphasizes the workload identity chain as the "before" state that participants verify — creates foundation for understanding what breaks in Module 5
- `/health` endpoint's independence from DB is highlighted early in Module 2, then revisited in Module 5 ("Notice how health checks still pass?") to teach observability lesson
- Exact Bicep resource reference (via workshop comment) makes the "make the change" step unambiguous for participants
- Module 5 emphasizes silent failure and the validity of broken Bicep — teaches that IaC syntax doesn't catch semantic errors
- Both modules include realistic curl commands and expected outputs (JSON responses, status codes) for concrete verification
- Troubleshooting sections designed for self-service learning without external help

**Key file paths:**
- `docs/02-deploy-application.md` — Module 2: Deploy Application (30 min); references k8s/deployment.yaml, server.js endpoints
- `docs/05-break-it.md` — Module 5: Break It (20 min); references infra/bicep/modules/identity.bicep (lines 58–67 for role assignment block)
- `infra/bicep/modules/identity.bicep` (line 58) — Contains the workshop comment marking the critical role assignment for removal in Module 5

### Module 1: Deploy Infrastructure (2026-04-12)

**Completed work:**
- `docs/01-deploy-infrastructure.md` — Module 1 guide covering infrastructure provisioning via GitHub Actions (~30 min)
- **2026-04-12 (updated):** Restructured deployment section to offer two options: Option A (GitHub Actions, recommended) and Option B (Local CLI)

**Module 1 structure and key content:**
- "What Gets Deployed" table sourced directly from main.bicep: 8 resources (AKS, CosmosDB, Log Analytics, Application Insights, UAMI, Federated Credential, role assignment, alert)
- Cluster configuration details: 2× Standard_DS2_v2 nodes, Kubernetes 1.30, OIDC issuer enabled, workload identity enabled
- **Option A (GitHub Actions):** Step-by-step workflow trigger: navigate to Actions → select workflow → configure location/workloadName inputs → run (10–15 min)
- **Option B (Local CLI):** Prerequisites (az CLI + jq), environment variables, 5-step process: create resource group → deploy Bicep → extract outputs via jq → display summary → save UAMI Client ID
- Deployment timeline: 10–15 minutes; includes expected final output with resource names and IDs
- Comprehensive verification section: 7 sequential az commands to validate all resources (cluster status, nodes, CosmosDB, managed identity)
- Expected outputs specified for each verification command (e.g., 2 nodes in Ready state, OIDC issuer enabled)
- ASCII architecture diagram: workload identity authentication chain from Pod → ServiceAccount → OIDC → Azure AD → CosmosDB RBAC
- Architecture section explains the full auth chain and why this design is critical to understand for Module 5 (role assignment removal)
- Troubleshooting section: 4 common failure modes (AuthorizationFailed, region not supported, quota exceeded, kubectl connection issues) with diagnosis and resolution steps
- Checkpoint verification: quick summary checklist of 6 items to confirm all resources created and nodes ready
- Cost reminder: explicitly states $0.40–0.50/hr while running and references Module 7 cleanup to stop costs
- **Note added:** Local deployment useful for testing/development; GitHub Actions recommended for full workshop (push trigger required for Module 5 fault injection)

**Key design decisions:**
- Sourced all resource names, region options, and node configuration from actual Bicep files (main.bicep, aks.bicep, monitoring.bicep) for accuracy
- GitHub Actions workflow parameters matched exactly from deploy-infra.yml (location dropdown with 3 options, workloadName text input with default "srelab")
- Emphasized workloadName consistency requirement early ("Keep this name handy — you'll need it in future modules") to prevent participant confusion in later modules
- Architecture diagram uses text-based flow to explain workload identity chain without requiring visual assets
- Troubleshooting solutions are self-service oriented (no "contact support") to maintain participant autonomy
- Verification section structured as sequential steps (get credentials → verify nodes → verify CosmosDB) to guide participants through the happy path
- Cost transparency: embedded cost reminder both in body and at end to reinforce budget awareness
- **Local CLI option design:** Mirrors GitHub Actions workflow commands exactly (same az commands, parameters, outputs) so both paths deploy identical infrastructure; uses jq to parse outputs for consistency with workflow
- **Clear trade-off messaging:** Explained that GitHub Actions is recommended due to push trigger on infra/** → enables Module 5 auto-deployment; local deployment requires manual re-run for Module 5 scenario

**Key file paths:**
- `docs/01-deploy-infrastructure.md` — Module 1: Deploy Infrastructure (30 min); references infra/bicep/main.bicep, .github/workflows/deploy-infra.yml
- `infra/bicep/main.bicep` (lines 1–136) — Orchestrator template; defines resource composition, parameters, outputs
- `infra/bicep/modules/aks.bicep` (line 16+) — AKS resource definition with workload identity and OIDC issuer configuration
- `infra/bicep/modules/monitoring.bicep` (lines 13–38) — Log Analytics and Application Insights resources
- `.github/workflows/deploy-infra.yml` — GitHub Actions workflow for infrastructure deployment; triggers on manual dispatch or infra/* push

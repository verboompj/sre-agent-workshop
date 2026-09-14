# App Service Handover Operational Guidelines

## Purpose

Use an approval-gated handoff from the Azure SRE Agent to the GitHub Copilot
coding agent. The SRE Agent investigates and proposes the handoff. Explicit
operator approval gates issue creation, and the operator retains control of
issue assignment, review, merge, and recovery.

## Incident policy

1. Investigate the alert and gather evidence before proposing a fix.
2. Correlate failed `POST /api/feature` requests with
   `NotImplementedException` telemetry and the connected repository.
3. Before requesting approval, verify that the target repository has GitHub
   Issues enabled and that no matching handoff issue is already open.
4. If issue creation returns HTTP 410 because Issues are disabled, do not create
   a branch, pull request, deployment, or alternate work item. Tell the operator
   to enable Issues or provide an approved alternative repository, then stop.
5. Do not make direct Azure changes or edit code during incident response.
6. Present the diagnosis and ask for explicit operator approval before creating
   a GitHub issue.
7. After approval, create exactly one issue without an assignee.
8. The learner reviews the created issue, then assigns
   `copilot-swe-agent`.
9. The SRE Agent must not create a branch or pull request, merge changes, or
   deploy the application. Those steps belong to the Copilot coding agent and
   operator.

## Required issue content

The issue must state:

- Route: `POST /api/feature`.
- Current behavior: HTTP 500.
- Expected behavior: HTTP 200 with exactly
  `{"status":"completed","message":"The unfinished feature is now implemented."}`.
- Preserve the existing `/health` behavior.
- Replace the test that documents the broken behavior with a test for the
  implemented success contract.
- Make code-only changes. Do not modify Bicep or GitHub Actions workflows.

## Recovery and closure

1. The learner assigns the reviewed issue to `copilot-swe-agent`.
2. The operator reviews and merges the Copilot pull request.
3. The operator updates the local `main` checkout and runs `deploy.sh` or
   `deploy.ps1` with the authenticated Azure CLI user.
4. Validate the endpoint and health check after deployment. Close the issue and
   incident only after recovery is confirmed.

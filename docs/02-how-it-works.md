# How the Azure SRE Agent works

> Shared concept (track-agnostic). Watched by the docs-freshness workflow.

## The incident loop

<!-- Signal (Azure Monitor alert) → Investigate (telemetry/KQL) → Hypothesize →
     Propose → (autonomy gate) → Remediate (GitHub issue / @copilot PR) → Validate. -->

## Autonomy levels

<!-- Read-only / suggest / act-with-approval; how to configure per environment. -->

## The GitHub loop

<!-- Agent files an issue, assigns @copilot, a PR restores desired state, merge redeploys. -->

## Guardrails

- The agent never makes silent direct changes → see [`knowledge/operational-guidelines.md`](./knowledge/operational-guidelines.md)
- Per-track approval gates (e.g. VM `invoke-approved-remediation`)

## Where each track plugs in

<!-- Point to workshops/<track>/docs/04-configure-incident-response (AKS) and the VM equivalent. -->

## Upstream references

<!-- Link learn.microsoft.com pages describing the agent workflow + autonomy. -->

# Scenario: VM Size Retirement (SKU Discontinuation)

> Track: `vm` · Scenario id: `vm-size-retirement`

## What breaks

Describe the fault and the symptom an attendee will observe.

## Inject the fault

```bash
./inject.sh    # bash / Linux
```
```powershell
./inject.ps1   # PowerShell / Windows
```

## Validate impact

```bash
./validate.sh
```

## Let the SRE Agent remediate

Explain what alert fires (`vm-size-retirement-alert`) and how the agent is expected
to investigate (see `query.kql`) and remediate (open an issue / PR).

## Manual remediation (facilitator fallback)

```bash
./remediate.sh
```

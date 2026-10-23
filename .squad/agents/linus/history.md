# Linus — History

## Core Context

- **Project:** A hands-on workshop introducing Azure SRE Agent capabilities within AKS through guided scenarios and Bicep infrastructure
- **Role:** Scenario Dev
- **Joined:** 2026-04-12T08:49:21.226Z

## Learnings

- Built the Node.js web app at `src/app/` — `server.js`, `package.json`, `Dockerfile`, `.dockerignore`
- CosmosDB client uses `aadCredentials: new DefaultAzureCredential()` (NOT connection strings) — critical for workload identity flow
- `/health` intentionally skips DB checks so pods stay Running even when CosmosDB auth fails; failures surface as 500s on `/items`
- `/items` error responses include the raw SDK error message so the SRE Agent can diagnose the root cause from pod logs
- Dockerfile uses multi-stage build with `node:20-alpine` and runs as non-root (`appuser`)
- Pinned dependency versions: express@4.21.2, @azure/identity@4.6.0, @azure/cosmos@4.2.0

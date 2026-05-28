# AKS Workshop Track

The AKS workshop remains the canonical cloud-native track and continues to use the existing repository paths and workflows.

## Compatibility-first layout

To avoid breaking current AKS scenarios, the implementation keeps the existing top-level assets as-is:

- `infra/bicep/` — Bicep modules
- `k8s/` — Kubernetes manifests
- `src/app/` — Node.js application
- `docs/00-07-*.md` — workshop modules
- `scripts/setup.*` and `scripts/cleanup.*` — pre/post helpers
- `.github/workflows/deploy-infra.yml` and `deploy-app.yml`

This folder serves as the AKS track entry point in the new `workshops/` organization while preserving current behavior.

## Start here

- Primary guide: [`../../README.md`](../../README.md)
- AKS modules: [`../../docs`](../../docs)


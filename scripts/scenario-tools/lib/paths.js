import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
// lib/ -> scenario-tools/ -> scripts/ -> repo root
export const REPO_ROOT = resolve(here, '..', '..', '..');
export const WORKSHOPS_DIR = resolve(REPO_ROOT, 'workshops');

// Closed set of tracks. `scopeParam` is the Bicep param name the generated
// aggregator declares and passes into each scenario alert's `scopeResourceId`.
export const TRACKS = {
  aks: { scopeParam: 'clusterId' },
  vm: { scopeParam: 'logAnalyticsResourceId' },
  appservice: { scopeParam: 'logAnalyticsResourceId' },
};

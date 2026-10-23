# Scenario Framework & Repository Future-Proofing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workshop scenarios self-contained, pluggable folders governed by one shared contract (manifest + schema + CI), relocate both tracks under `workshops/<track>/`, add a shared concept layer, and add a weekly docs-freshness agent.

**Architecture:** Each scenario becomes a vertical-slice folder (`scenarios/<id>/`) with a `scenario.yaml` manifest validated by JSON Schema. Node-based tooling in `scripts/scenario-tools/` validates manifests and *generates* the per-track alert aggregator, `INDEX.md`, and README tables (eliminating hand-maintained scatter points). The investigation tooling becomes manifest-driven. AKS relocates to `workshops/aks/` symmetric with `workshops/vm/`.

**Tech Stack:** Node.js 22+ (ESM, built-in `node --test`), `ajv` + `ajv-formats` (JSON Schema draft 2020-12), `js-yaml`, Bicep (`az bicep build`), GitHub Actions, GitHub Agentic Workflows (`gh-aw`).

**Source spec:** `docs/superpowers/specs/2026-06-10-scenario-framework-design.md` (on branch `design/scenario-framework`).

---

## Conventions for every task

- **Commits:** Conventional Commits + required trailer. Every commit message ends with:
  ```
  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
  ```
- **Bicep build check:** `az bicep build --file <path> --stdout > /dev/null` (standalone `bicep` is not on PATH; `az bicep` is v0.42.1).
- **Node tests:** run from `scripts/scenario-tools/` with `npm test` (alias for `node --test`).
- **Generated files are never hand-edited:** `workshops/<track>/scenarios/INDEX.md`, `workshops/<track>/infra/bicep/modules/scenario-alerts.bicep`, and the README scenario table between `<!-- BEGIN SCENARIOS -->` / `<!-- END SCENARIOS -->` markers are produced by `scripts/validate-scenarios.sh --write`.
- **Branch:** implement on a feature branch off `design/scenario-framework` (or off `main` after the spec/plan merge). Do **not** implement on `feat/vm-workshop-bash-scripts` (unrelated WIP).

---

## File Structure (what each new file owns)

```
schemas/scenario.schema.json                     # the manifest contract (draft 2020-12)
scripts/
├── new-scenario.sh                              # thin wrapper → scenario-tools/bin/new-scenario.js
├── validate-scenarios.sh                        # thin wrapper → generate (--write) + validate
└── scenario-tools/                              # Node package (the contract's engine)
    ├── package.json
    ├── package-lock.json
    ├── lib/
    │   ├── paths.js                             # REPO_ROOT, WORKSHOPS_DIR, TRACKS map
    │   ├── scenarios.js                         # discover + load scenario.yaml folders
    │   ├── validate.js                          # makeValidator() + checkScenario() (pure)
    │   └── generate.js                          # renderIndex/renderReadmeBlock/renderAggregator (pure)
    ├── bin/
    │   ├── validate.js                          # CLI: schema + cross-field + drift checks
    │   ├── generate.js                          # CLI: write INDEX/aggregator/README table
    │   └── new-scenario.js                      # CLI: scaffold from template/
    ├── template/                                # canonical copy-me scenario (valid by construction)
    │   ├── scenario.yaml  README.md  query.kql  alert.bicep
    │   ├── inject.sh  inject.ps1
    │   ├── remediate.sh  remediate.ps1
    │   └── validate.sh  validate.ps1
    └── test/
        ├── validate.test.js
        ├── generate.test.js
        └── template.test.js
.github/workflows/
├── validate-scenarios.yml                       # CI test harness for the contract
├── deploy-aks-infra.yml   (renamed)             # repathed to workshops/aks/**
├── deploy-aks-app.yml     (renamed)
├── publish-aks-image.yml  (renamed)
├── validate-aks-infra.yml (renamed)
└── sre-docs-freshness.md + .lock.yml            # weekly docs-freshness agent
CONTRIBUTING.md                                  # add-a-scenario / add-a-track guide
docs/00-what-is-sre-agent.md 01-why-... 02-how-...# shared concept layer (Phase 4)
workshops/
├── README.md                                    # track index
├── aks/{docs,infra,k8s,src,scripts,scenarios}/  # relocated AKS (Phase 3)
└── vm/scenarios/{disk-full,iis-app-pool,cpu-runaway}/  # adopted VM scenarios (Phase 2)
```

## Phase 1 — Scenario Framework Foundation (additive, low risk)

No existing files move in this phase. It delivers the schema, the Node tooling, the template, the shell wrappers, and the CI workflow. Verified entirely by unit tests + a template self-validation test; it does **not** touch `workshops/`.

### Task 1.1: Scaffold the `scenario-tools` Node package

**Files:**
- Create: `scripts/scenario-tools/package.json`
- Create: `scripts/scenario-tools/lib/paths.js`

- [ ] **Step 1: Create `package.json`**

```json
{
  "name": "scenario-tools",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "description": "Validation and generation tooling for SRE Agent Workshop scenarios.",
  "scripts": {
    "test": "node --test",
    "validate": "node bin/validate.js",
    "generate": "node bin/generate.js"
  },
  "dependencies": {
    "ajv": "^8.17.1",
    "ajv-formats": "^3.0.1",
    "js-yaml": "^4.1.0"
  }
}
```

- [ ] **Step 2: Create `lib/paths.js`** (resolves the repo root from `lib/` and declares the closed set of tracks + their alert scope wiring)

```js
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
};
```

- [ ] **Step 3: Install dependencies and create the lockfile**

Run: `cd scripts/scenario-tools && npm install`
Expected: creates `node_modules/` and `package-lock.json`; exit 0.

- [ ] **Step 4: Verify the package runs the (empty) test runner**

Run: `cd scripts/scenario-tools && npm test`
Expected: `node --test` exits 0 with `tests 0` (no test files yet).

- [ ] **Step 5: Ignore `node_modules` and commit**

Add `scripts/scenario-tools/node_modules/` to the repo `.gitignore` (create the line if absent), then:

```bash
git add .gitignore scripts/scenario-tools/package.json scripts/scenario-tools/package-lock.json scripts/scenario-tools/lib/paths.js
git commit -m "feat(scenarios): scaffold scenario-tools node package"
```

### Task 1.2: The manifest JSON Schema

**Files:**
- Create: `schemas/scenario.schema.json`

- [ ] **Step 1: Create the schema** (draft 2020-12)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/JoranBergfeld/sre-agent-workshop/schemas/scenario.schema.json",
  "title": "SRE Agent Workshop Scenario",
  "type": "object",
  "additionalProperties": false,
  "required": ["id", "title", "track", "summary", "severity", "inject", "validate", "docPage"],
  "properties": {
    "id": { "type": "string", "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$" },
    "title": { "type": "string", "minLength": 1 },
    "track": { "type": "string", "enum": ["aks", "vm"] },
    "summary": { "type": "string", "minLength": 1 },
    "severity": { "type": "integer", "minimum": 0, "maximum": 4 },
    "estimatedMinutes": { "type": "integer", "minimum": 1 },
    "difficulty": { "type": "string", "enum": ["beginner", "intermediate", "advanced"] },
    "learningObjectives": { "type": "array", "items": { "type": "string", "minLength": 1 } },
    "signal": {
      "type": "object",
      "additionalProperties": false,
      "required": ["alertModule", "alertName"],
      "properties": {
        "alertModule": { "type": "string" },
        "alertName": { "type": "string" }
      }
    },
    "inject": { "$ref": "#/$defs/scriptPair" },
    "validate": { "$ref": "#/$defs/scriptPair" },
    "remediate": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["action", "bash", "powershell"],
        "properties": {
          "action": { "type": "string", "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$" },
          "bash": { "type": "string" },
          "powershell": { "type": "string" },
          "description": { "type": "string" }
        }
      }
    },
    "investigation": {
      "type": "object",
      "additionalProperties": false,
      "required": ["query"],
      "properties": { "query": { "type": "string" } }
    },
    "docPage": { "type": "string" }
  },
  "$defs": {
    "scriptPair": {
      "type": "object",
      "additionalProperties": false,
      "required": ["bash", "powershell"],
      "properties": {
        "bash": { "type": "string" },
        "powershell": { "type": "string" }
      }
    }
  }
}
```

- [ ] **Step 2: Verify the schema compiles under ajv**

Run:
```bash
cd scripts/scenario-tools && node -e "import('ajv/dist/2020.js').then(async ({default:Ajv})=>{const af=(await import('ajv-formats')).default;const fs=await import('node:fs');const a=new Ajv({allErrors:true,strict:false});af(a);a.compile(JSON.parse(fs.readFileSync('../../schemas/scenario.schema.json','utf8')));console.log('schema OK')})"
```
Expected: prints `schema OK`.

- [ ] **Step 3: Commit**

```bash
git add schemas/scenario.schema.json
git commit -m "feat(scenarios): add scenario manifest JSON schema"
```

### Task 1.3: `lib/validate.js` — cross-field checks (TDD)

**Files:**
- Create: `scripts/scenario-tools/lib/validate.js`
- Test: `scripts/scenario-tools/test/validate.test.js`

- [ ] **Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkScenario } from '../lib/validate.js';

const baseManifest = {
  id: 'disk-full', title: 'Disk Full', track: 'vm', summary: 's', severity: 2,
  inject: { bash: 'inject.sh', powershell: 'inject.ps1' },
  validate: { bash: 'validate.sh', powershell: 'validate.ps1' },
  docPage: 'README.md',
};
const present = new Set(['inject.sh', 'inject.ps1', 'validate.sh', 'validate.ps1', 'scenario.yaml', 'README.md']);
const fileExists = (p) => present.has(p.split('/').pop());

test('valid scenario yields no cross-field errors', () => {
  const errs = checkScenario(
    { track: 'vm', id: 'disk-full', manifest: baseManifest, dir: '/x/disk-full' },
    { fileExists }
  );
  assert.deepEqual(errs, []);
});

test('id must equal folder name', () => {
  const errs = checkScenario(
    { track: 'vm', id: 'other', manifest: baseManifest, dir: '/x/other' },
    { fileExists }
  );
  assert.ok(errs.some((e) => e.includes('must equal folder name')));
});

test('track must equal parent track directory', () => {
  const errs = checkScenario(
    { track: 'aks', id: 'disk-full', manifest: baseManifest, dir: '/x/disk-full' },
    { fileExists }
  );
  assert.ok(errs.some((e) => e.includes('must equal parent track')));
});

test('missing powershell injector is reported', () => {
  const fe = (p) => fileExists(p) && !p.endsWith('inject.ps1');
  const errs = checkScenario(
    { track: 'vm', id: 'disk-full', manifest: baseManifest, dir: '/x/disk-full' },
    { fileExists: fe }
  );
  assert.ok(errs.some((e) => e.includes('inject.powershell references missing file')));
});

test('non-executable .sh is reported', () => {
  const errs = checkScenario(
    { track: 'vm', id: 'disk-full', manifest: baseManifest, dir: '/x/disk-full' },
    { fileExists, isExecutable: () => false }
  );
  assert.ok(errs.some((e) => e.includes('must be executable')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts/scenario-tools && node --test test/validate.test.js`
Expected: FAIL — cannot find module `../lib/validate.js`.

- [ ] **Step 3: Implement `lib/validate.js`**

```js
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import Ajv from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { REPO_ROOT } from './paths.js';

export function makeValidator() {
  const schema = JSON.parse(
    readFileSync(resolve(REPO_ROOT, 'schemas', 'scenario.schema.json'), 'utf8')
  );
  const ajv = new Ajv({ allErrors: true, strict: false });
  addFormats(ajv);
  return ajv.compile(schema);
}

// Pure cross-field validation. `fileExists` and `isExecutable` are injected so
// the logic is testable without touching the filesystem. Executable checks
// apply only to `.sh` scripts.
export function checkScenario({ track, id, manifest, dir }, { fileExists, isExecutable = () => true }) {
  const errors = [];

  if (manifest.id !== id) errors.push(`id "${manifest.id}" must equal folder name "${id}"`);
  if (manifest.track !== track) errors.push(`track "${manifest.track}" must equal parent track "${track}"`);

  for (const f of ['scenario.yaml', manifest.docPage].filter(Boolean)) {
    if (!fileExists(resolve(dir, f))) errors.push(`missing required file ${f}`);
  }

  const checkScript = (label, f) => {
    if (!f) { errors.push(`${label} is required`); return; }
    if (!fileExists(resolve(dir, f))) { errors.push(`${label} references missing file ${f}`); return; }
    if (f.endsWith('.sh') && !isExecutable(resolve(dir, f))) {
      errors.push(`${label} ${f} must be executable (chmod +x)`);
    }
  };

  for (const kind of ['inject', 'validate']) {
    const pair = manifest[kind] ?? {};
    checkScript(`${kind}.bash`, pair.bash);
    checkScript(`${kind}.powershell`, pair.powershell);
  }

  for (const action of manifest.remediate ?? []) {
    checkScript(`remediate.${action.action}.bash`, action.bash);
    checkScript(`remediate.${action.action}.powershell`, action.powershell);
  }

  if (manifest.signal?.alertModule && !fileExists(resolve(dir, manifest.signal.alertModule))) {
    errors.push(`signal.alertModule references missing file ${manifest.signal.alertModule}`);
  }
  if (manifest.investigation?.query && !fileExists(resolve(dir, manifest.investigation.query))) {
    errors.push(`investigation.query references missing file ${manifest.investigation.query}`);
  }

  return errors;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts/scenario-tools && node --test test/validate.test.js`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/scenario-tools/lib/validate.js scripts/scenario-tools/test/validate.test.js
git commit -m "feat(scenarios): add manifest cross-field validation"
```

### Task 1.4: `lib/generate.js` — render INDEX / README table / aggregator (TDD)

**Files:**
- Create: `scripts/scenario-tools/lib/generate.js`
- Test: `scripts/scenario-tools/test/generate.test.js`

- [ ] **Step 1: Write the failing test**

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  kebabToCamel, renderIndex, renderAggregator, renderReadmeBlock,
  README_BEGIN, README_END,
} from '../lib/generate.js';

const scenarios = [
  { id: 'disk-full', track: 'vm', manifest: { id: 'disk-full', title: 'Disk Full', severity: 2, summary: 'C: fills up', estimatedMinutes: 20, difficulty: 'beginner', signal: { alertModule: 'alert.bicep', alertName: 'x' } } },
  { id: 'cpu-runaway', track: 'vm', manifest: { id: 'cpu-runaway', title: 'CPU Runaway', severity: 3, summary: 'CPU pegged', signal: { alertModule: 'alert.bicep', alertName: 'y' } } },
];

test('kebabToCamel converts ids to bicep symbols', () => {
  assert.equal(kebabToCamel('disk-full'), 'diskFull');
  assert.equal(kebabToCamel('cosmos-rbac-removal'), 'cosmosRbacRemoval');
});

test('renderIndex lists scenarios sorted by id with a generated-note', () => {
  const md = renderIndex('vm', scenarios);
  assert.match(md, /# VM Scenarios/);
  assert.match(md, /do not edit by hand/);
  assert.ok(md.indexOf('cpu-runaway') < md.indexOf('disk-full'));
  assert.match(md, /\[Disk Full\]\(disk-full\/\)/);
});

test('renderAggregator emits one module per alert-bearing scenario with camel symbols', () => {
  const bicep = renderAggregator('vm', scenarios);
  assert.match(bicep, /param logAnalyticsResourceId string/);
  assert.match(bicep, /module cpuRunawayAlert '\.\.\/\.\.\/\.\.\/scenarios\/cpu-runaway\/alert\.bicep'/);
  assert.match(bicep, /scopeResourceId: logAnalyticsResourceId/);
});

test('renderAggregator scopes AKS alerts to clusterId', () => {
  const aks = renderAggregator('aks', [
    { id: 'cosmos-rbac-removal', track: 'aks', manifest: { id: 'cosmos-rbac-removal', title: 'X', severity: 3, summary: 's', signal: { alertModule: 'alert.bicep', alertName: 'z' } } },
  ]);
  assert.match(aks, /param clusterId string/);
  assert.match(aks, /scopeResourceId: clusterId/);
});

test('renderReadmeBlock wraps the table in markers with scenarios/ link prefix', () => {
  const block = renderReadmeBlock(scenarios);
  assert.ok(block.startsWith(README_BEGIN));
  assert.ok(block.trimEnd().endsWith(README_END));
  assert.match(block, /\[Disk Full\]\(scenarios\/disk-full\/\)/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts/scenario-tools && node --test test/generate.test.js`
Expected: FAIL — cannot find module `../lib/generate.js`.

- [ ] **Step 3: Implement `lib/generate.js`**

```js
import { TRACKS } from './paths.js';

const GEN_NOTE = '<!-- Generated by scripts/validate-scenarios.sh — do not edit by hand. -->';
export const README_BEGIN = '<!-- BEGIN SCENARIOS -->';
export const README_END = '<!-- END SCENARIOS -->';

export function kebabToCamel(s) {
  return s.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

function sortById(scenarios) {
  return scenarios.slice().sort((a, b) => a.id.localeCompare(b.id));
}

function renderTable(scenarios, linkPrefix = '') {
  const rows = sortById(scenarios).map((s) => {
    const m = s.manifest;
    const mins = m.estimatedMinutes ? `${m.estimatedMinutes}m` : '—';
    const diff = m.difficulty ?? '—';
    return `| [${m.title}](${linkPrefix}${s.id}/) | ${m.severity} | ${mins} | ${diff} | ${m.summary} |`;
  });
  return [
    '| Scenario | Severity | Est. | Difficulty | Summary |',
    '| --- | --- | --- | --- | --- |',
    ...rows,
  ].join('\n');
}

export function renderIndex(track, scenarios) {
  return [`# ${track.toUpperCase()} Scenarios`, '', GEN_NOTE, '', renderTable(scenarios, ''), ''].join('\n');
}

export function renderReadmeBlock(scenarios) {
  return [README_BEGIN, GEN_NOTE, '', renderTable(scenarios, 'scenarios/'), '', README_END].join('\n');
}

export function renderAggregator(track, scenarios) {
  const cfg = TRACKS[track];
  if (!cfg) throw new Error(`Unknown track: ${track}`);
  const withAlerts = sortById(scenarios.filter((s) => s.manifest.signal?.alertModule));

  const header = [
    '// GENERATED by scripts/scenario-tools — do not edit by hand.',
    `// Aggregates per-scenario alert modules for the ${track} track.`,
    '',
    "@description('Azure region for alert resources')",
    'param location string',
    '',
    "@description('Base workload name for resource naming')",
    'param workloadName string',
    '',
    "@description('Resource tags')",
    'param tags object',
    '',
    "@description('Scope resource ID each scenario alert binds to')",
    `param ${cfg.scopeParam} string`,
    '',
  ];

  const modules = withAlerts.flatMap((s) => {
    const sym = `${kebabToCamel(s.id)}Alert`;
    const rel = `../../../scenarios/${s.id}/${s.manifest.signal.alertModule}`;
    return [
      `module ${sym} '${rel}' = {`,
      `  name: 'alert-${s.id}'`,
      '  params: {',
      '    location: location',
      '    workloadName: workloadName',
      '    tags: tags',
      `    scopeResourceId: ${cfg.scopeParam}`,
      '  }',
      '}',
      '',
    ];
  });

  return [...header, ...modules].join('\n');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts/scenario-tools && node --test test/generate.test.js`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/scenario-tools/lib/generate.js scripts/scenario-tools/test/generate.test.js
git commit -m "feat(scenarios): add index/readme/aggregator generators"
```

### Task 1.5: `lib/scenarios.js` — discovery + loading

**Files:**
- Create: `scripts/scenario-tools/lib/scenarios.js`

- [ ] **Step 1: Implement `lib/scenarios.js`** (no unit test — it is thin filesystem glue exercised end-to-end by the template test in Task 1.9 and the CLIs)

```js
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import yaml from 'js-yaml';
import { WORKSHOPS_DIR, TRACKS } from './paths.js';

function scenariosRoot(track) {
  return resolve(WORKSHOPS_DIR, track, 'scenarios');
}

export function listTracks() {
  return Object.keys(TRACKS).filter((t) => existsSync(scenariosRoot(t)));
}

export function scenarioDirs(track) {
  const root = scenariosRoot(track);
  if (!existsSync(root)) return [];
  return readdirSync(root)
    .filter((name) => !name.startsWith('_') && !name.startsWith('.'))
    .map((name) => resolve(root, name))
    .filter((dir) => statSync(dir).isDirectory());
}

export function loadScenario(dir) {
  const id = basename(dir);
  const manifest = yaml.load(readFileSync(resolve(dir, 'scenario.yaml'), 'utf8'));
  return { id, track: manifest?.track, dir, manifest };
}

export function loadAllScenarios() {
  const out = [];
  for (const track of listTracks()) {
    for (const dir of scenarioDirs(track)) out.push({ track, ...loadScenario(dir) });
  }
  return out;
}
```

- [ ] **Step 2: Commit**

```bash
git add scripts/scenario-tools/lib/scenarios.js
git commit -m "feat(scenarios): add scenario discovery and loading"
```

### Task 1.6: `bin/generate.js` and `bin/validate.js` CLIs

**Files:**
- Create: `scripts/scenario-tools/bin/generate.js`
- Create: `scripts/scenario-tools/bin/validate.js`

- [ ] **Step 1: Implement `bin/generate.js`**

```js
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { WORKSHOPS_DIR } from '../lib/paths.js';
import { listTracks, scenarioDirs, loadScenario } from '../lib/scenarios.js';
import { renderIndex, renderAggregator, renderReadmeBlock, README_BEGIN, README_END } from '../lib/generate.js';

function writeReadmeBlock(readmePath, block) {
  if (!existsSync(readmePath)) return;
  const src = readFileSync(readmePath, 'utf8');
  const re = new RegExp(`${README_BEGIN}[\\s\\S]*?${README_END}`);
  if (!re.test(src)) return;
  writeFileSync(readmePath, src.replace(re, block.trimEnd()));
}

for (const track of listTracks()) {
  const scenarios = scenarioDirs(track).map(loadScenario);
  const trackDir = resolve(WORKSHOPS_DIR, track);

  writeFileSync(resolve(trackDir, 'scenarios', 'INDEX.md'), renderIndex(track, scenarios));

  const modulesDir = resolve(trackDir, 'infra', 'bicep', 'modules');
  if (existsSync(modulesDir)) {
    writeFileSync(resolve(modulesDir, 'scenario-alerts.bicep'), renderAggregator(track, scenarios));
  }

  writeReadmeBlock(resolve(trackDir, 'README.md'), renderReadmeBlock(scenarios));
  console.log(`generated ${track}: ${scenarios.length} scenario(s)`);
}
```

- [ ] **Step 2: Implement `bin/validate.js`**

```js
import { existsSync, readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { WORKSHOPS_DIR } from '../lib/paths.js';
import { listTracks, scenarioDirs, loadScenario } from '../lib/scenarios.js';
import { makeValidator, checkScenario } from '../lib/validate.js';
import { renderIndex, renderAggregator, renderReadmeBlock, README_BEGIN, README_END } from '../lib/generate.js';

const fileExists = (p) => existsSync(p);
const isExecutable = (p) => {
  try { return (statSync(p).mode & 0o111) !== 0; } catch { return false; }
};

const validate = makeValidator();
let failed = false;
const fail = (msg) => { console.error(`✖ ${msg}`); failed = true; };

for (const track of listTracks()) {
  const scenarios = scenarioDirs(track).map(loadScenario);

  for (const s of scenarios) {
    if (!validate(s.manifest)) {
      for (const e of validate.errors) fail(`${track}/${s.id}: schema ${e.instancePath || '/'} ${e.message}`);
      continue;
    }
    for (const e of checkScenario(s, { fileExists, isExecutable })) fail(`${track}/${s.id}: ${e}`);
  }

  const trackDir = resolve(WORKSHOPS_DIR, track);

  const indexPath = resolve(trackDir, 'scenarios', 'INDEX.md');
  if (!existsSync(indexPath) || readFileSync(indexPath, 'utf8') !== renderIndex(track, scenarios)) {
    fail(`${track}: scenarios/INDEX.md is stale — run scripts/validate-scenarios.sh --write`);
  }

  const modulesDir = resolve(trackDir, 'infra', 'bicep', 'modules');
  if (existsSync(modulesDir)) {
    const aggPath = resolve(modulesDir, 'scenario-alerts.bicep');
    if (!existsSync(aggPath) || readFileSync(aggPath, 'utf8') !== renderAggregator(track, scenarios)) {
      fail(`${track}: modules/scenario-alerts.bicep is stale — run scripts/validate-scenarios.sh --write`);
    }
  }

  const readmePath = resolve(trackDir, 'README.md');
  if (existsSync(readmePath)) {
    const src = readFileSync(readmePath, 'utf8');
    const re = new RegExp(`${README_BEGIN}[\\s\\S]*?${README_END}`);
    const m = src.match(re);
    if (m && m[0] !== renderReadmeBlock(scenarios).trimEnd()) {
      fail(`${track}: README scenario table is stale — run scripts/validate-scenarios.sh --write`);
    }
  }
}

if (failed) { console.error('\nScenario validation FAILED'); process.exit(1); }
console.log('Scenario validation passed');
```

- [ ] **Step 3: Smoke-run both CLIs** (no scenarios exist yet, so both must succeed and be no-ops)

Run: `cd scripts/scenario-tools && node bin/generate.js && node bin/validate.js`
Expected: `generate.js` prints nothing (no tracks with a `scenarios/` dir yet) and `validate.js` prints `Scenario validation passed`; exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/scenario-tools/bin/generate.js scripts/scenario-tools/bin/validate.js
git commit -m "feat(scenarios): add generate and validate CLIs"
```

### Task 1.7: `bin/new-scenario.js` scaffolder

**Files:**
- Create: `scripts/scenario-tools/bin/new-scenario.js`

- [ ] **Step 1: Implement `bin/new-scenario.js`**

```js
import { cpSync, existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import { WORKSHOPS_DIR, TRACKS } from '../lib/paths.js';

const [track, id, ...titleParts] = process.argv.slice(2);
const title = titleParts.join(' ') || id;

if (!track || !id) {
  console.error('Usage: new-scenario.js <track> <id> [Title Words...]');
  process.exit(2);
}
if (!TRACKS[track]) {
  console.error(`Unknown track "${track}". Known tracks: ${Object.keys(TRACKS).join(', ')}`);
  process.exit(2);
}
if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(id)) {
  console.error(`Invalid id "${id}". Use kebab-case (e.g. disk-full).`);
  process.exit(2);
}

const templateDir = resolve(import.meta.dirname, '..', 'template');
const dest = resolve(WORKSHOPS_DIR, track, 'scenarios', id);
if (existsSync(dest)) {
  console.error(`Scenario already exists: ${dest}`);
  process.exit(1);
}

cpSync(templateDir, dest, { recursive: true });

const tokens = { __SCENARIO_ID__: id, __SCENARIO_TITLE__: title, __TRACK__: track };
const substitute = (dir) => {
  for (const name of readdirSync(dir)) {
    const p = resolve(dir, name);
    if (statSync(p).isDirectory()) { substitute(p); continue; }
    let txt = readFileSync(p, 'utf8');
    for (const [k, v] of Object.entries(tokens)) txt = txt.split(k).join(v);
    writeFileSync(p, txt);
  }
};
substitute(dest);

console.log(`Created ${track}/${id} at ${dest}\n`);
console.log('Next steps:');
console.log(`  1. Edit scenario.yaml (summary, severity, estimatedMinutes, difficulty).`);
console.log(`  2. Implement inject/remediate/validate scripts (.sh + .ps1).`);
console.log(`  3. Fill in query.kql and alert.bicep (or delete signal/investigation if unused).`);
console.log(`  4. Write README.md.`);
console.log(`  5. Run: scripts/validate-scenarios.sh --write`);
console.log(`  6. chmod +x ${track}/scenarios/${id}/*.sh`);
```

- [ ] **Step 2: Commit** (cannot run yet — the template is created in Task 1.8)

```bash
git add scripts/scenario-tools/bin/new-scenario.js
git commit -m "feat(scenarios): add new-scenario scaffolder"
```

### Task 1.8: The canonical scenario template

**Files (all under `scripts/scenario-tools/template/`):**
- Create: `scenario.yaml`, `README.md`, `query.kql`, `alert.bicep`, `inject.sh`, `inject.ps1`, `remediate.sh`, `remediate.ps1`, `validate.sh`, `validate.ps1`

The template must be **valid by construction** after token substitution. Tokens: `__SCENARIO_ID__`, `__SCENARIO_TITLE__`, `__TRACK__`.

- [ ] **Step 1: Create `template/scenario.yaml`**

```yaml
id: __SCENARIO_ID__
title: __SCENARIO_TITLE__
track: __TRACK__
summary: One-line description of the fault and its user-visible symptom.
severity: 3
estimatedMinutes: 20
difficulty: beginner
learningObjectives:
  - Describe what the attendee learns from this scenario.
signal:
  alertModule: alert.bicep
  alertName: __SCENARIO_ID__-alert
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: restore
    bash: remediate.sh
    powershell: remediate.ps1
    description: Undo the injected fault.
investigation:
  query: query.kql
docPage: README.md
```

- [ ] **Step 2: Create `template/README.md`** (the embedded markdown intentionally contains fenced code, so this file is shown here inside a 4-backtick fence)

````markdown
# Scenario: __SCENARIO_TITLE__

> Track: `__TRACK__` · Scenario id: `__SCENARIO_ID__`

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

Explain what alert fires (`__SCENARIO_ID__-alert`) and how the agent is expected
to investigate (see `query.kql`) and remediate (open an issue / PR).

## Manual remediation (facilitator fallback)

```bash
./remediate.sh
```
````

- [ ] **Step 3: Create `template/query.kql`** (`{{VM_NAME}}` is the placeholder the VM investigation tool substitutes; harmless for AKS)

```kusto
// Investigation query for __SCENARIO_TITLE__.
// The VM investigation tool replaces {{VM_NAME}} with the target VM name.
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where Resource contains "{{VM_NAME}}"
| take 50
```

- [ ] **Step 4: Create `template/alert.bicep`** (standard scenario alert signature — `scopeResourceId`)

```bicep
@description('Azure region for the alert')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (cluster or Log Analytics workspace)')
param scopeResourceId string

resource alert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-__SCENARIO_ID__-alert'
  location: location
  tags: tags
  properties: {
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [scopeResourceId]
    criteria: {
      allOf: [
        {
          query: 'AzureDiagnostics | where TimeGenerated > ago(5m) | count'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    autoMitigate: false
  }
}
```

- [ ] **Step 5: Create the six scripts** (`inject.sh`, `remediate.sh`, `validate.sh`, and `.ps1` peers)

`template/inject.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "TODO: inject the __SCENARIO_ID__ fault."
exit 0
```

`template/remediate.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "TODO: remediate the __SCENARIO_ID__ fault."
exit 0
```

`template/validate.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "TODO: validate impact of the __SCENARIO_ID__ fault."
exit 0
```

`template/inject.ps1`:
```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
Write-Host "TODO: inject the __SCENARIO_ID__ fault."
```

`template/remediate.ps1`:
```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
Write-Host "TODO: remediate the __SCENARIO_ID__ fault."
```

`template/validate.ps1`:
```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
Write-Host "TODO: validate impact of the __SCENARIO_ID__ fault."
```

- [ ] **Step 6: Mark the shell scripts executable and verify the template builds**

Run:
```bash
chmod +x scripts/scenario-tools/template/*.sh
sed 's/__SCENARIO_ID__/example/g; s/__TRACK__/vm/g' scripts/scenario-tools/template/alert.bicep > /tmp/tpl-alert.bicep
az bicep build --file /tmp/tpl-alert.bicep --stdout > /dev/null && echo "template alert builds"
```
Expected: prints `template alert builds`.

- [ ] **Step 7: Commit**

```bash
git add scripts/scenario-tools/template
git commit -m "feat(scenarios): add canonical scenario template"
```

### Task 1.9: Template self-validation test (TDD safety net)

**Files:**
- Create: `scripts/scenario-tools/test/template.test.js`

- [ ] **Step 1: Write the test** (substitutes tokens into a temp dir, then asserts it passes schema + `checkScenario`)

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, basename } from 'node:path';
import { tmpdir } from 'node:os';
import yaml from 'js-yaml';
import { makeValidator, checkScenario } from '../lib/validate.js';

function materialize(track, id) {
  const tmp = mkdtempSync(resolve(tmpdir(), 'scn-'));
  const dest = resolve(tmp, id);
  cpSync(resolve(import.meta.dirname, '..', 'template'), dest, { recursive: true });
  const tokens = { __SCENARIO_ID__: id, __TRACK__: track, __SCENARIO_TITLE__: 'Example' };
  const walk = (d) => {
    for (const n of readdirSync(d)) {
      const p = resolve(d, n);
      if (statSync(p).isDirectory()) { walk(p); continue; }
      let t = readFileSync(p, 'utf8');
      for (const [k, v] of Object.entries(tokens)) t = t.split(k).join(v);
      writeFileSync(p, t);
    }
  };
  walk(dest);
  return dest;
}

test('template passes schema and cross-field checks after substitution', () => {
  const dir = materialize('vm', 'example');
  const manifest = yaml.load(readFileSync(resolve(dir, 'scenario.yaml'), 'utf8'));
  const validate = makeValidator();
  assert.ok(validate(manifest), JSON.stringify(validate.errors));
  const errs = checkScenario(
    { track: 'vm', id: basename(dir), manifest, dir },
    { fileExists: (p) => existsSync(p), isExecutable: () => true }
  );
  assert.deepEqual(errs, []);
});
```

- [ ] **Step 2: Run the full test suite**

Run: `cd scripts/scenario-tools && npm test`
Expected: PASS — all tests across `validate.test.js`, `generate.test.js`, `template.test.js`.

- [ ] **Step 3: Verify the scaffolder end-to-end into a throwaway track dir, then discard**

Run (a pure scaffolder smoke test — do **not** run generate/validate here, since at Phase 1 no `scenarios/` exists yet and generating would create untracked `INDEX.md`/aggregator files):
```bash
node scripts/scenario-tools/bin/new-scenario.js vm selftest-demo "Self Test"
test -f workshops/vm/scenarios/selftest-demo/scenario.yaml \
  && test -x workshops/vm/scenarios/selftest-demo/inject.sh \
  && echo "scaffold OK"
rm -rf workshops/vm/scenarios/selftest-demo
rmdir workshops/vm/scenarios 2>/dev/null || true
```
Expected: scaffolder prints the next-steps checklist; `scaffold OK` confirms the manifest exists and the copied `.sh` kept its exec bit. Cleanup leaves `workshops/vm/` with no `scenarios/` dir (use a non-`_`-prefixed id like `selftest-demo` — discovery skips `_`-prefixed names).

- [ ] **Step 4: Commit**

```bash
git add scripts/scenario-tools/test/template.test.js
git commit -m "test(scenarios): assert template validates by construction"
```

### Task 1.10: Shell wrappers

**Files:**
- Create: `scripts/new-scenario.sh`
- Create: `scripts/validate-scenarios.sh`

- [ ] **Step 1: Create `scripts/new-scenario.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/scenario-tools"
[ -d "$TOOLS_DIR/node_modules" ] || (cd "$TOOLS_DIR" && npm install --silent)
node "$TOOLS_DIR/bin/new-scenario.js" "$@"
```

- [ ] **Step 2: Create `scripts/validate-scenarios.sh`** (`--write` regenerates, then always validates)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/scenario-tools"
[ -d "$TOOLS_DIR/node_modules" ] || (cd "$TOOLS_DIR" && npm install --silent)
if [ "${1:-}" = "--write" ]; then
  node "$TOOLS_DIR/bin/generate.js"
fi
node "$TOOLS_DIR/bin/validate.js"
```

- [ ] **Step 3: Mark executable and smoke-test**

Run:
```bash
chmod +x scripts/new-scenario.sh scripts/validate-scenarios.sh
scripts/validate-scenarios.sh
```
Expected: `Scenario validation passed`.

- [ ] **Step 4: Commit**

```bash
git add scripts/new-scenario.sh scripts/validate-scenarios.sh
git commit -m "feat(scenarios): add new-scenario and validate-scenarios wrappers"
```

### Task 1.11: CI workflow for the contract

**Files:**
- Create: `.github/workflows/validate-scenarios.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: Validate Scenarios

on:
  push:
    paths:
      - 'workshops/**/scenarios/**'
      - 'schemas/scenario.schema.json'
      - 'scripts/scenario-tools/**'
  pull_request:
    paths:
      - 'workshops/**/scenarios/**'
      - 'schemas/scenario.schema.json'
      - 'scripts/scenario-tools/**'

permissions:
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'

      - name: Install scenario-tools
        working-directory: scripts/scenario-tools
        run: npm ci

      - name: Unit tests
        working-directory: scripts/scenario-tools
        run: npm test

      - name: Validate scenarios (schema + drift)
        run: node scripts/scenario-tools/bin/validate.js

      - name: Set up Bicep
        run: az bicep install

      - name: Build all scenario + aggregator bicep
        run: |
          shopt -s nullglob
          for f in workshops/*/scenarios/*/alert.bicep workshops/*/infra/bicep/modules/scenario-alerts.bicep; do
            echo "Building $f"
            az bicep build --file "$f" --stdout > /dev/null
          done
```

- [ ] **Step 2: Lint the workflow YAML locally**

Run: `cd scripts/scenario-tools && node --input-type=module -e "import fs from 'node:fs'; import yaml from 'js-yaml'; yaml.load(fs.readFileSync('../../.github/workflows/validate-scenarios.yml','utf8')); console.log('workflow YAML OK')"`
Expected: prints `workflow YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/validate-scenarios.yml
git commit -m "ci(scenarios): validate manifests, tests, and bicep on PR"
```

**Phase 1 complete:** the contract, engine, template, wrappers, and CI exist and are green, with zero changes to `workshops/`.

## Phase 2 — Adopt VM Scenarios into the Framework (medium risk)

Converts the three existing VM scenarios into self-contained `scenarios/<id>/` slices, decomposes the monolithic `alerts.bicep` into per-scenario `alert.bicep`, makes the investigation **and** approval-gated remediation tools manifest-driven, and relocates the watch/cleanup docs. Net effect: adding a 4th VM scenario later requires **zero** edits to shared tooling or infra.

> **Design note (gap caught during planning):** `workshops/vm/tools/invoke-approved-remediation.sh` and `Invoke-ApprovedRemediation.ps1` currently resolve remediation scripts from `../scripts/remediation/<action>.{sh,ps1}` with a hardcoded action allow-list. Moving the scripts into scenario folders breaks them. Task 2.6 rewrites both to glob `../scenarios/*/<action>.{sh,ps1}`, making the manifests the single source of truth for approved actions. Task 2.6 also adds a per-track action-name uniqueness check so the glob is unambiguous.

**Naming convention adopted here:** inside each scenario folder the single injector is `inject.{sh,ps1}`; each remediation script keeps its **action name** as its stem (`cleanup-disk.sh`, `cleanup-temp.sh`, `start-iis-app-pool.sh`, `stop-cpu-runaway.sh`) so manifest `action` == file stem == approval-gate `--action`.

### Task 2.1: `disk-full` scenario slice

**Files:**
- Move: `workshops/vm/scripts/scenarios/inject-disk-full.sh` → `workshops/vm/scenarios/disk-full/inject.sh` (and `.ps1`)
- Move: `workshops/vm/scripts/remediation/cleanup-disk.sh` → `workshops/vm/scenarios/disk-full/cleanup-disk.sh` (and `.ps1`)
- Move: `workshops/vm/scripts/remediation/cleanup-temp.sh` → `workshops/vm/scenarios/disk-full/cleanup-temp.sh` (and `.ps1`)
- Move: `workshops/vm/docs/03-scenario-disk-full.md` → `workshops/vm/scenarios/disk-full/README.md`
- Create: `workshops/vm/scenarios/disk-full/scenario.yaml`, `alert.bicep`, `query.kql`, `validate.sh`, `validate.ps1`

- [ ] **Step 1: Move scripts and doc with `git mv`** (relative `../../tools/...` refs are preserved — both old and new paths are two levels under `workshops/vm/`)

```bash
mkdir -p workshops/vm/scenarios/disk-full
git mv workshops/vm/scripts/scenarios/inject-disk-full.sh   workshops/vm/scenarios/disk-full/inject.sh
git mv workshops/vm/scripts/scenarios/inject-disk-full.ps1  workshops/vm/scenarios/disk-full/inject.ps1
git mv workshops/vm/scripts/remediation/cleanup-disk.sh     workshops/vm/scenarios/disk-full/cleanup-disk.sh
git mv workshops/vm/scripts/remediation/cleanup-disk.ps1    workshops/vm/scenarios/disk-full/cleanup-disk.ps1
git mv workshops/vm/scripts/remediation/cleanup-temp.sh     workshops/vm/scenarios/disk-full/cleanup-temp.sh
git mv workshops/vm/scripts/remediation/cleanup-temp.ps1    workshops/vm/scenarios/disk-full/cleanup-temp.ps1
git mv workshops/vm/docs/03-scenario-disk-full.md           workshops/vm/scenarios/disk-full/README.md
```

- [ ] **Step 2: Create `scenario.yaml`**

```yaml
id: disk-full
title: Disk Full (C: Pressure)
track: vm
summary: A runaway process fills C:\Temp until free space drops below 10%, degrading the IIS workload.
severity: 2
estimatedMinutes: 25
difficulty: beginner
learningObjectives:
  - Correlate a disk-pressure alert to the offending folder via Azure Monitor Perf data.
  - Drive remediation through the approval gate instead of ad-hoc deletion.
signal:
  alertModule: alert.bicep
  alertName: vm-disk-pressure
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: cleanup-disk
    bash: cleanup-disk.sh
    powershell: cleanup-disk.ps1
    description: Remove the injected fill files from C:\Temp\diskfill.
  - action: cleanup-temp
    bash: cleanup-temp.sh
    powershell: cleanup-temp.ps1
    description: Approved Temp-folder cleanup (constrained path allow-list).
investigation:
  query: query.kql
docPage: README.md
```

- [ ] **Step 3: Create `alert.bicep`** (decomposed from `alerts.bicep` `diskPressureAlert`, standard `scopeResourceId` signature)

```bicep
@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (Log Analytics workspace)')
param scopeResourceId string

resource diskPressureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-vm-disk-pressure'
  location: location
  tags: tags
  properties: {
    displayName: 'VM Disk Free Space Critical'
    description: 'Alerts when C: free space drops below 10 percent on workshop VMs.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      scopeResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "LogicalDisk" and CounterName == "% Free Space" and InstanceName == "C:"
            | summarize FreeSpace=min(CounterValue) by Computer, bin(TimeGenerated, 5m)
          '''
          metricMeasureColumn: 'FreeSpace'
          timeAggregation: 'Average'
          operator: 'LessThan'
          threshold: 10
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}
```

- [ ] **Step 4: Create `query.kql`** (extracted from `invoke-vm-investigation.sh` disk-full branch; `{{VM_NAME}}` placeholder)

```kusto
Perf
| where ObjectName == "LogicalDisk" and CounterName == "% Free Space" and InstanceName == "C:"
| where Computer has "{{VM_NAME}}"
| top 5 by TimeGenerated desc
```

- [ ] **Step 5: Create `validate.sh`** (thin wrapper delegating to the shared smoke test; `../../scripts/validation/smoke-test.sh` resolves correctly from the scenario folder)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../scripts/validation/smoke-test.sh" "$@"
```

- [ ] **Step 6: Create `validate.ps1`**

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\..\..\scripts\validation\smoke-test.ps1" @args
```

- [ ] **Step 7: Mark wrappers executable and build the alert**

```bash
chmod +x workshops/vm/scenarios/disk-full/validate.sh
az bicep build --file workshops/vm/scenarios/disk-full/alert.bicep --stdout > /dev/null && echo "disk-full alert builds"
```
Expected: `disk-full alert builds`.

- [ ] **Step 8: Update in-README script references** (the moved doc still points at the old `scripts/scenarios/...` paths)

In `workshops/vm/scenarios/disk-full/README.md`, replace path references so they are scenario-relative:
- `.\workshops\vm\scripts\scenarios\inject-disk-full.ps1` → `.\inject.ps1`
- `./workshops/vm/scripts/scenarios/inject-disk-full.sh` → `./inject.sh` (if present)
- Keep `Invoke-VmInvestigation` / `Invoke-ApprovedRemediation` references as `..\..\tools\...` (now two levels up from the scenario folder).

Run to confirm no stale references remain:
```bash
grep -n "scripts/scenarios\|scripts\\\\scenarios" workshops/vm/scenarios/disk-full/README.md || echo "no stale inject paths"
```
Expected: `no stale inject paths`.

- [ ] **Step 9: Commit**

```bash
git add workshops/vm/scenarios/disk-full
git commit -m "feat(vm): adopt disk-full as a self-contained scenario"
```

### Task 2.2: `iis-app-pool` scenario slice

**Files:**
- Move: `workshops/vm/scripts/scenarios/stop-iis-app-pool.{sh,ps1}` → `workshops/vm/scenarios/iis-app-pool/inject.{sh,ps1}`
- Move: `workshops/vm/scripts/remediation/start-iis-app-pool.{sh,ps1}` → `workshops/vm/scenarios/iis-app-pool/start-iis-app-pool.{sh,ps1}`
- Move: `workshops/vm/docs/04-scenario-iis-app-pool.md` → `workshops/vm/scenarios/iis-app-pool/README.md`
- Create: `scenario.yaml`, `alert.bicep`, `query.kql`, `validate.sh`, `validate.ps1`

- [ ] **Step 1: Move with `git mv`**

```bash
mkdir -p workshops/vm/scenarios/iis-app-pool
git mv workshops/vm/scripts/scenarios/stop-iis-app-pool.sh   workshops/vm/scenarios/iis-app-pool/inject.sh
git mv workshops/vm/scripts/scenarios/stop-iis-app-pool.ps1  workshops/vm/scenarios/iis-app-pool/inject.ps1
git mv workshops/vm/scripts/remediation/start-iis-app-pool.sh  workshops/vm/scenarios/iis-app-pool/start-iis-app-pool.sh
git mv workshops/vm/scripts/remediation/start-iis-app-pool.ps1 workshops/vm/scenarios/iis-app-pool/start-iis-app-pool.ps1
git mv workshops/vm/docs/04-scenario-iis-app-pool.md           workshops/vm/scenarios/iis-app-pool/README.md
```

- [ ] **Step 2: Create `scenario.yaml`**

```yaml
id: iis-app-pool
title: IIS App Pool Failure
track: vm
summary: The IIS application pool is stopped, returning 503s until the pool is restarted.
severity: 2
estimatedMinutes: 20
difficulty: beginner
learningObjectives:
  - Detect a stopped IIS app pool from Windows Event telemetry.
  - Restart the pool through the approval gate.
signal:
  alertModule: alert.bicep
  alertName: vm-iis-app-pool-failure
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: start-iis-app-pool
    bash: start-iis-app-pool.sh
    powershell: start-iis-app-pool.ps1
    description: Start the stopped IIS application pool.
investigation:
  query: query.kql
docPage: README.md
```

- [ ] **Step 3: Create `alert.bicep`** (decomposed from `iisFailureAlert`)

```bicep
@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (Log Analytics workspace)')
param scopeResourceId string

resource iisFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-vm-iis-app-pool-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'IIS App Pool Failure'
    description: 'Alerts when IIS service/app pool state transitions indicate stopped workload.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      scopeResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Event
            | where Source has "IIS" or EventLog == "System"
            | where RenderedDescription has "stopped" or RenderedDescription has "terminated"
            | summarize FailureCount=count() by Computer, bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}
```

- [ ] **Step 4: Create `query.kql`** (from the iis-app-pool branch)

```kusto
Event
| where Computer has "{{VM_NAME}}"
| where RenderedDescription has "stopped" or Source has "IIS"
| top 5 by TimeGenerated desc
```

- [ ] **Step 5: Create `validate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../scripts/validation/smoke-test.sh" "$@"
```

- [ ] **Step 6: Create `validate.ps1`**

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\..\..\scripts\validation\smoke-test.ps1" @args
```

- [ ] **Step 7: Mark executable, build alert, scrub stale README paths**

```bash
chmod +x workshops/vm/scenarios/iis-app-pool/validate.sh
az bicep build --file workshops/vm/scenarios/iis-app-pool/alert.bicep --stdout > /dev/null && echo "iis alert builds"
```
Then in `workshops/vm/scenarios/iis-app-pool/README.md` replace `...\scripts\scenarios\stop-iis-app-pool.ps1` → `.\inject.ps1` (and the `.sh` peer), and fix any `..\tools\` depth to `..\..\tools\`.

- [ ] **Step 8: Commit**

```bash
git add workshops/vm/scenarios/iis-app-pool
git commit -m "feat(vm): adopt iis-app-pool as a self-contained scenario"
```

### Task 2.3: `cpu-runaway` scenario slice

**Files:**
- Move: `workshops/vm/scripts/scenarios/inject-cpu-runaway.{sh,ps1}` → `workshops/vm/scenarios/cpu-runaway/inject.{sh,ps1}`
- Move: `workshops/vm/scripts/remediation/stop-cpu-runaway.{sh,ps1}` → `workshops/vm/scenarios/cpu-runaway/stop-cpu-runaway.{sh,ps1}`
- Move: `workshops/vm/docs/05-scenario-cpu-runaway.md` → `workshops/vm/scenarios/cpu-runaway/README.md`
- Create: `scenario.yaml`, `alert.bicep`, `query.kql`, `validate.sh`, `validate.ps1`

- [ ] **Step 1: Move with `git mv`**

```bash
mkdir -p workshops/vm/scenarios/cpu-runaway
git mv workshops/vm/scripts/scenarios/inject-cpu-runaway.sh   workshops/vm/scenarios/cpu-runaway/inject.sh
git mv workshops/vm/scripts/scenarios/inject-cpu-runaway.ps1  workshops/vm/scenarios/cpu-runaway/inject.ps1
git mv workshops/vm/scripts/remediation/stop-cpu-runaway.sh   workshops/vm/scenarios/cpu-runaway/stop-cpu-runaway.sh
git mv workshops/vm/scripts/remediation/stop-cpu-runaway.ps1  workshops/vm/scenarios/cpu-runaway/stop-cpu-runaway.ps1
git mv workshops/vm/docs/05-scenario-cpu-runaway.md           workshops/vm/scenarios/cpu-runaway/README.md
```

- [ ] **Step 2: Create `scenario.yaml`**

```yaml
id: cpu-runaway
title: CPU Runaway
track: vm
summary: A runaway process pegs CPU above 85%, starving the IIS workload of compute.
severity: 3
estimatedMinutes: 20
difficulty: beginner
learningObjectives:
  - Identify sustained high CPU from Azure Monitor Perf counters.
  - Stop the offending process through the approval gate.
signal:
  alertModule: alert.bicep
  alertName: vm-cpu-runaway
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: stop-cpu-runaway
    bash: stop-cpu-runaway.sh
    powershell: stop-cpu-runaway.ps1
    description: Stop the runaway CPU process.
investigation:
  query: query.kql
docPage: README.md
```

- [ ] **Step 3: Create `alert.bicep`** (decomposed from `cpuRunawayAlert`)

```bicep
@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (Log Analytics workspace)')
param scopeResourceId string

resource cpuRunawayAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-vm-cpu-runaway'
  location: location
  tags: tags
  properties: {
    displayName: 'VM CPU Runaway'
    description: 'Alerts when CPU exceeds 85 percent on workshop VMs.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      scopeResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
            | summarize AvgCpu=avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
          '''
          metricMeasureColumn: 'AvgCpu'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 85
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}
```

- [ ] **Step 4: Create `query.kql`** (from the default/cpu branch)

```kusto
Perf
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| where Computer has "{{VM_NAME}}"
| top 5 by TimeGenerated desc
```

- [ ] **Step 5: Create `validate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../scripts/validation/smoke-test.sh" "$@"
```

- [ ] **Step 6: Create `validate.ps1`**

```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\..\..\scripts\validation\smoke-test.ps1" @args
```

- [ ] **Step 7: Mark executable, build alert, scrub stale README paths**

```bash
chmod +x workshops/vm/scenarios/cpu-runaway/validate.sh
az bicep build --file workshops/vm/scenarios/cpu-runaway/alert.bicep --stdout > /dev/null && echo "cpu alert builds"
```
Then in `workshops/vm/scenarios/cpu-runaway/README.md` replace `...\scripts\scenarios\inject-cpu-runaway.ps1` → `.\inject.ps1` (and `.sh` peer), and fix `..\tools\` depth to `..\..\tools\`.

- [ ] **Step 8: Commit**

```bash
git add workshops/vm/scenarios/cpu-runaway
git commit -m "feat(vm): adopt cpu-runaway as a self-contained scenario"
```

### Task 2.4: Replace monolithic `alerts.bicep` with the generated aggregator

**Files:**
- Delete: `workshops/vm/infra/bicep/modules/alerts.bicep`
- Generate: `workshops/vm/infra/bicep/modules/scenario-alerts.bicep` (via tooling)
- Modify: `workshops/vm/infra/bicep/main.bicep:90-98`

- [ ] **Step 1: Generate the aggregator + INDEX from the three manifests**

Run: `scripts/validate-scenarios.sh --write`
Expected: prints `generated vm: 3 scenario(s)`; creates `workshops/vm/infra/bicep/modules/scenario-alerts.bicep` and `workshops/vm/scenarios/INDEX.md`.

- [ ] **Step 2: Inspect the generated aggregator**

Run: `cat workshops/vm/infra/bicep/modules/scenario-alerts.bicep`
Expected: declares `param logAnalyticsResourceId string` and three modules (`cpuRunawayAlert`, `diskFullAlert`, `iisAppPoolAlert`) each pointing at `../../../scenarios/<id>/alert.bicep` with `scopeResourceId: logAnalyticsResourceId`.

- [ ] **Step 3: Delete the old monolithic module**

```bash
git rm workshops/vm/infra/bicep/modules/alerts.bicep
```

- [ ] **Step 4: Rewire `main.bicep`** — replace the old module call (currently lines 90-98) with a call to the generated aggregator, dropping the now-unused `logAnalyticsWorkspaceId` param

Old block:
```bicep
module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logAnalyticsResourceId: monitoring.outputs.logAnalyticsId
  }
}
```
New block:
```bicep
module alerts 'modules/scenario-alerts.bicep' = {
  name: 'alerts'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    logAnalyticsResourceId: monitoring.outputs.logAnalyticsId
  }
}
```

- [ ] **Step 5: Build the whole VM template**

Run: `az bicep build --file workshops/vm/infra/bicep/main.bicep --stdout > /dev/null && echo "vm main builds"`
Expected: `vm main builds` (no warnings about unused params or missing modules).

- [ ] **Step 6: Validate drift**

Run: `scripts/validate-scenarios.sh`
Expected: `Scenario validation passed`.

- [ ] **Step 7: Commit**

```bash
git add workshops/vm/infra/bicep/main.bicep workshops/vm/infra/bicep/modules/scenario-alerts.bicep workshops/vm/scenarios/INDEX.md
git rm --cached workshops/vm/infra/bicep/modules/alerts.bicep 2>/dev/null || true
git commit -m "refactor(vm): generate per-scenario alerts, drop monolithic alerts.bicep"
```

### Task 2.5: Make the investigation tool manifest-driven

**Files:**
- Modify: `workshops/vm/tools/invoke-vm-investigation.sh:29-32,52-62`
- Modify: `workshops/vm/tools/Invoke-VmInvestigation.ps1:8,28-39`

- [ ] **Step 1 (bash): remove the scenario allow-list `case`** (lines 29-32). Delete:
```bash
case "$SCENARIO" in
  disk-full|iis-app-pool|cpu-runaway) ;;
  *) echo "Invalid scenario: $SCENARIO. Allowed: disk-full, iis-app-pool, cpu-runaway." >&2; exit 2 ;;
esac
```

- [ ] **Step 2 (bash): replace the KQL `case`** (lines 52-62) with a `query.kql` read + placeholder substitution:
```bash
QUERY_FILE="$SCRIPT_DIR/../scenarios/$SCENARIO/query.kql"
if [ ! -f "$QUERY_FILE" ]; then
  echo "Unknown scenario '$SCENARIO': no query file at $QUERY_FILE" >&2
  exit 2
fi
KQL=$(sed "s/{{VM_NAME}}/$VM_NAME/g" "$QUERY_FILE")
```

- [ ] **Step 3 (bash): verify**

Run:
```bash
bash -n workshops/vm/tools/invoke-vm-investigation.sh && echo "syntax OK"
workshops/vm/tools/invoke-vm-investigation.sh --scenario disk-full --vm-name testvm
```
Expected: `syntax OK`; the run produces a trace + postmortem under `workshops/vm/output/` and exits 0 (WorkspaceId omitted → KQL read but query skipped). A bogus `--scenario nope` must exit 2.
> Clean up generated artifacts afterward: `git checkout -- workshops/vm/output 2>/dev/null; git clean -f workshops/vm/output >/dev/null` (leave the two pre-existing sample logs intact — only remove newly generated ones).

- [ ] **Step 4 (ps1): remove `[ValidateSet(...)]`** on line 8 so `$Scenario` accepts any id:
```powershell
    [string]$Scenario = "disk-full"
```

- [ ] **Step 5 (ps1): replace the `switch ($Scenario)` block** (lines 28-39) with a `query.kql` read:
```powershell
$queryFile = Join-Path $PSScriptRoot "..\scenarios\$Scenario\query.kql"
if (-not (Test-Path $queryFile)) {
    throw "Unknown scenario '$Scenario': no query file at $queryFile"
}
$kql = (Get-Content $queryFile -Raw).Replace('{{VM_NAME}}', $VmName)
```

- [ ] **Step 6: Commit**

```bash
git add workshops/vm/tools/invoke-vm-investigation.sh workshops/vm/tools/Invoke-VmInvestigation.ps1
git commit -m "refactor(vm): drive investigation queries from scenario query.kql"
```

### Task 2.6: Make the approval gate manifest-governed (glob + uniqueness)

**Files:**
- Modify: `scripts/scenario-tools/lib/validate.js` (add `findDuplicateActions`)
- Modify: `scripts/scenario-tools/test/validate.test.js` (add a test)
- Modify: `scripts/scenario-tools/bin/validate.js` (call the new check per track)
- Modify: `workshops/vm/tools/invoke-approved-remediation.sh:47-48` (script-path resolution + allow-list)
- Modify: `workshops/vm/tools/Invoke-ApprovedRemediation.ps1` (action map → glob)

- [ ] **Step 1: Write the failing test** for cross-scenario action uniqueness (append to `test/validate.test.js`)

```js
import { findDuplicateActions } from '../lib/validate.js';

test('findDuplicateActions flags an action reused across scenarios', () => {
  const scenarios = [
    { id: 'a', manifest: { remediate: [{ action: 'restart' }] } },
    { id: 'b', manifest: { remediate: [{ action: 'restart' }, { action: 'flush' }] } },
  ];
  const dups = findDuplicateActions(scenarios);
  assert.deepEqual(dups, [{ action: 'restart', ids: ['a', 'b'] }]);
});

test('findDuplicateActions returns empty when all unique', () => {
  const scenarios = [
    { id: 'a', manifest: { remediate: [{ action: 'cleanup-disk' }] } },
    { id: 'b', manifest: { remediate: [{ action: 'start-iis-app-pool' }] } },
  ];
  assert.deepEqual(findDuplicateActions(scenarios), []);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd scripts/scenario-tools && node --test test/validate.test.js`
Expected: FAIL — `findDuplicateActions` is not exported.

- [ ] **Step 3: Implement `findDuplicateActions`** (append to `lib/validate.js`)

```js
// Approval-gate actions are resolved by globbing scenarios/*/<action>.sh, so an
// action name must be unique within a track. Returns [{action, ids}] for clashes.
export function findDuplicateActions(scenarios) {
  const byAction = new Map();
  for (const s of scenarios) {
    for (const r of s.manifest.remediate ?? []) {
      if (!byAction.has(r.action)) byAction.set(r.action, []);
      byAction.get(r.action).push(s.id);
    }
  }
  return [...byAction.entries()]
    .filter(([, ids]) => ids.length > 1)
    .map(([action, ids]) => ({ action, ids }));
}
```

- [ ] **Step 4: Run it to confirm it passes**

Run: `cd scripts/scenario-tools && node --test test/validate.test.js`
Expected: PASS.

- [ ] **Step 5: Wire the check into `bin/validate.js`** — add the import and a per-track check inside the existing `for (const track of listTracks())` loop, right after the per-scenario loop:

Add to the imports at the top:
```js
import { makeValidator, checkScenario, findDuplicateActions } from '../lib/validate.js';
```
Add after the `for (const s of scenarios)` loop body:
```js
  for (const dup of findDuplicateActions(scenarios)) {
    fail(`${track}: remediation action "${dup.action}" is defined by multiple scenarios (${dup.ids.join(', ')}); action names must be unique per track`);
  }
```

- [ ] **Step 6: Rewrite the bash approval gate to glob scenario folders.** In `workshops/vm/tools/invoke-approved-remediation.sh`:

Replace the hardcoded validation `case` (the block that restricts `cleanup-disk|cleanup-temp|start-iis-app-pool|stop-cpu-runaway`) and the `SCRIPT_PATH="$SCRIPT_DIR/../scripts/remediation/${ACTION}.sh"` line with a glob lookup. The new action-resolution block (replacing both the old allow-list `case` and the old `SCRIPT_PATH=` line):
```bash
if [ -z "$ACTION" ]; then
  echo "Action is required." >&2
  exit 2
fi

# Resolve the action to a remediation script owned by a scenario. The scenario
# manifests (validated in CI) are the single source of truth for allowed actions.
# nullglob keeps the array empty (rather than a literal pattern) when nothing matches;
# this is portable to bash 3.2 (macOS) unlike `mapfile`.
shopt -s nullglob
MATCHES=("$SCRIPT_DIR"/../scenarios/*/"${ACTION}.sh")
shopt -u nullglob
if [ "${#MATCHES[@]}" -eq 0 ]; then
  echo "Unknown action '$ACTION': no scenarios/*/${ACTION}.sh found." >&2
  exit 1
fi
if [ "${#MATCHES[@]}" -gt 1 ]; then
  echo "Ambiguous action '$ACTION' matches multiple scenarios; action names must be unique." >&2
  exit 1
fi
SCRIPT_PATH="${MATCHES[0]}"
```
Also update the `--help` usage string to read: `--action <name>  (any remediation action defined by a scenario)`.

- [ ] **Step 7: Rewrite the PowerShell approval gate.** In `workshops/vm/tools/Invoke-ApprovedRemediation.ps1`:

Remove `[ValidateSet(...)]` from the `$Action` parameter, and replace the `$actionMap = @{...}` hashtable + `$scriptPath = $actionMap[$Action]` lookup with a glob:
```powershell
$matches = @(Get-ChildItem -Path (Join-Path $PSScriptRoot "..\scenarios\*\$Action.ps1") -ErrorAction SilentlyContinue)
if ($matches.Count -eq 0) {
    throw "Unknown action '$Action': no scenarios\*\$Action.ps1 found."
}
if ($matches.Count -gt 1) {
    throw "Ambiguous action '$Action' matches multiple scenarios; action names must be unique."
}
$scriptPath = $matches[0].FullName
```

- [ ] **Step 8: Verify both gates resolve a real action and reject a bogus one**

Run:
```bash
bash -n workshops/vm/tools/invoke-approved-remediation.sh && echo "syntax OK"
printf 'APPROVE\n' | workshops/vm/tools/invoke-approved-remediation.sh --action nope --change-ticket CHG-1 || echo "rejected unknown (expected)"
ls workshops/vm/scenarios/*/cleanup-disk.sh
scripts/validate-scenarios.sh
```
Expected: `syntax OK`; unknown action rejected; the glob lists `workshops/vm/scenarios/disk-full/cleanup-disk.sh`; `Scenario validation passed`.

- [ ] **Step 9: Commit**

```bash
git add scripts/scenario-tools/lib/validate.js scripts/scenario-tools/test/validate.test.js scripts/scenario-tools/bin/validate.js workshops/vm/tools/invoke-approved-remediation.sh workshops/vm/tools/Invoke-ApprovedRemediation.ps1
git commit -m "refactor(vm): resolve approved remediations from scenario folders"
```

### Task 2.7: Relocate watch/cleanup docs and wire the VM README table

**Files:**
- Move: `workshops/vm/docs/06-watch-agent-workflow.md` → `workshops/vm/docs/90-watch-agent-workflow.md`
- Move: `workshops/vm/docs/07-cleanup.md` → `workshops/vm/docs/99-cleanup.md`
- Modify: `workshops/vm/README.md:31-35`
- Regenerate: VM `scenarios/INDEX.md` + README scenario table

- [ ] **Step 1: Move the docs**

```bash
git mv workshops/vm/docs/06-watch-agent-workflow.md workshops/vm/docs/90-watch-agent-workflow.md
git mv workshops/vm/docs/07-cleanup.md workshops/vm/docs/99-cleanup.md
```

- [ ] **Step 2: Fix any cross-links to the renamed/moved docs**

Run to find references:
```bash
grep -rn "06-watch-agent-workflow\|07-cleanup\|03-scenario-disk-full\|04-scenario-iis-app-pool\|05-scenario-cpu-runaway" workshops/vm
```
Update each hit: `06-watch-agent-workflow.md`→`90-watch-agent-workflow.md`, `07-cleanup.md`→`99-cleanup.md`. Scenario-doc links from other docs become `../scenarios/<id>/README.md` (from a `docs/` file) or `./<id>/` (from the INDEX).

- [ ] **Step 3: Replace the README "Workshop modules" scenario entries with nav + a generated table.** In `workshops/vm/README.md`, replace lines 31-35:
```markdown
- [03. Scenario 1: Disk Full](./docs/03-scenario-disk-full.md)
- [04. Scenario 2: IIS App Pool Failure](./docs/04-scenario-iis-app-pool.md)
- [05. Scenario 3: CPU Runaway](./docs/05-scenario-cpu-runaway.md)
- [06. Watch Agent Workflow](./docs/06-watch-agent-workflow.md)
- [07. Cleanup](./docs/07-cleanup.md)
```
with:
```markdown
- [90. Watch Agent Workflow](./docs/90-watch-agent-workflow.md)
- [99. Cleanup](./docs/99-cleanup.md)

## Scenarios

<!-- BEGIN SCENARIOS -->
<!-- END SCENARIOS -->
```

- [ ] **Step 4: Generate the table into the markers**

Run: `scripts/validate-scenarios.sh --write`
Expected: `generated vm: 3 scenario(s)`; the README now has a populated scenario table between the markers, and `scenarios/INDEX.md` lists all three scenarios.

- [ ] **Step 5: Validate**

Run: `scripts/validate-scenarios.sh`
Expected: `Scenario validation passed`.

- [ ] **Step 6: Confirm the legacy script subfolders are empty and remove them**

Run:
```bash
ls -A workshops/vm/scripts/scenarios workshops/vm/scripts/remediation 2>/dev/null || echo "already gone"
rmdir workshops/vm/scripts/scenarios workshops/vm/scripts/remediation 2>/dev/null || true
```
Expected: both directories are empty (all files moved) and removed. `workshops/vm/scripts/` now contains only `access/`, `validation/`, `setup.*`, `cleanup.*`, `README.md`.

- [ ] **Step 7: Update `workshops/vm/scripts/README.md`** if it documents the removed `scenarios/` and `remediation/` folders — point readers to `workshops/vm/scenarios/<id>/` for inject/remediation scripts. (Inspect first: `grep -n "scenarios\|remediation" workshops/vm/scripts/README.md`.)

- [ ] **Step 8: Commit**

```bash
git add workshops/vm
git commit -m "docs(vm): relocate watch/cleanup docs and generate scenario index"
```

**Phase 2 complete:** all three VM scenarios are self-contained, alerts are generated, both tools are manifest-driven, and the approval gate's allow-list is the manifests themselves.

## Phase 3 — Relocate AKS Track + Adopt its Scenario (highest risk)

Makes the two tracks structurally symmetric: AKS moves from the repo root into `workshops/aks/`, its `http500Alert` becomes the `cosmos-rbac-removal` scenario's `alert.bicep`, its four workflows are renamed + repathed, and redirect stubs preserve old doc links. The `cosmosRoleAssignment` in `identity.bicep` (the declarative baseline the agent restores) **stays**; the scenario's runtime inject/remediate scripts simulate break/fix via `az`.

> **Risk control:** this phase is a large `git mv` set. Do it on a dedicated branch, run `az bicep build` + `scripts/validate-scenarios.sh` after each task, and keep each task in its own commit so a bad move is easy to revert.

### Task 3.1: Relocate the AKS file tree under `workshops/aks/`

**Files (git mv):**
- `infra/` → `workshops/aks/infra/`
- `k8s/` → `workshops/aks/k8s/`
- `src/` → `workshops/aks/src/`
- `scripts/{setup,cleanup}.{sh,ps1}` → `workshops/aks/scripts/`
- `docs/00..04` → `workshops/aks/docs/00..04`; `docs/06` → `workshops/aks/docs/90-watch-sre-agent.md`; `docs/07` → `workshops/aks/docs/99-cleanup.md`
- `docs/05-break-it.md` → `workshops/aks/scenarios/cosmos-rbac-removal/README.md`

- [ ] **Step 1: Move infra, k8s, src**

```bash
mkdir -p workshops/aks
git mv infra workshops/aks/infra
git mv k8s   workshops/aks/k8s
git mv src   workshops/aks/src
```

- [ ] **Step 2: Move the AKS-specific scripts** (top-level `scripts/` becomes repo-tooling only: `scenario-tools/`, `new-scenario.sh`, `validate-scenarios.sh`)

```bash
mkdir -p workshops/aks/scripts
git mv scripts/setup.sh    workshops/aks/scripts/setup.sh
git mv scripts/setup.ps1   workshops/aks/scripts/setup.ps1
git mv scripts/cleanup.sh  workshops/aks/scripts/cleanup.sh
git mv scripts/cleanup.ps1 workshops/aks/scripts/cleanup.ps1
```

- [ ] **Step 3: Move the setup/scenario docs**

```bash
mkdir -p workshops/aks/docs workshops/aks/scenarios/cosmos-rbac-removal
git mv docs/00-prerequisites.md            workshops/aks/docs/00-prerequisites.md
git mv docs/01-deploy-infrastructure.md    workshops/aks/docs/01-deploy-infrastructure.md
git mv docs/02-deploy-application.md       workshops/aks/docs/02-deploy-application.md
git mv docs/03-onboard-sre-agent.md        workshops/aks/docs/03-onboard-sre-agent.md
git mv docs/04-configure-incident-response.md workshops/aks/docs/04-configure-incident-response.md
git mv docs/06-watch-sre-agent.md          workshops/aks/docs/90-watch-sre-agent.md
git mv docs/07-cleanup.md                  workshops/aks/docs/99-cleanup.md
git mv docs/05-break-it.md                 workshops/aks/scenarios/cosmos-rbac-removal/README.md
```

- [ ] **Step 4: Fix the one path reference inside `setup.sh`** (`workshops/aks/scripts/setup.sh:102` mentions the relocated module)

Replace `infra/bicep/modules/aks.bicep` with `workshops/aks/infra/bicep/modules/aks.bicep` in `workshops/aks/scripts/setup.sh`. Then scan both moved scripts for any other stale paths:
```bash
grep -nE "(^|[^/])infra/|(^|[^/])k8s/|(^|[^/])src/" workshops/aks/scripts/setup.sh workshops/aks/scripts/cleanup.sh || echo "no other stale paths"
```

- [ ] **Step 5: Verify the relocated Bicep still builds**

Run: `az bicep build --file workshops/aks/infra/bicep/main.bicep --stdout > /dev/null && echo "aks main builds (relocated)"`
Expected: `aks main builds (relocated)` (module refs are relative, so the move is transparent).

- [ ] **Step 6: Commit the relocation**

```bash
git add -A
git commit -m "refactor(aks): relocate AKS track under workshops/aks"
```

### Task 3.2: Build the `cosmos-rbac-removal` scenario

**Files (create under `workshops/aks/scenarios/cosmos-rbac-removal/`):**
- `scenario.yaml`, `alert.bicep`, `query.kql`, `inject.sh`, `inject.ps1`, `remediate.sh`, `remediate.ps1`, `validate.sh`, `validate.ps1`
- (`README.md` already moved in Task 3.1)

- [ ] **Step 1: Create `scenario.yaml`**

```yaml
id: cosmos-rbac-removal
title: CosmosDB RBAC Removal
track: aks
summary: The app's managed-identity CosmosDB role assignment is deleted, so /items returns HTTP 500 while /health stays green.
severity: 3
estimatedMinutes: 25
difficulty: intermediate
learningObjectives:
  - Distinguish liveness (healthy) from dependency failure (500 on /items).
  - Trace 5xx errors in ContainerLog to a missing CosmosDB RBAC role assignment.
  - Drive remediation through a GitHub issue / @copilot PR (GitOps), with a manual fallback.
signal:
  alertModule: alert.bicep
  alertName: http-500-errors
inject:
  bash: inject.sh
  powershell: inject.ps1
validate:
  bash: validate.sh
  powershell: validate.ps1
remediate:
  - action: restore-cosmos-rbac
    bash: remediate.sh
    powershell: remediate.ps1
    description: Recreate the Cosmos DB Built-in Data Contributor role assignment for the workload UAMI and restart pods.
investigation:
  query: query.kql
docPage: README.md
```

- [ ] **Step 2: Create `alert.bicep`** (decomposed from `main.bicep` `http500Alert`, standard `scopeResourceId` signature)

```bicep
@description('Azure region for alert resources')
param location string

@description('Base workload name for resource naming')
param workloadName string

@description('Resource tags')
param tags object

@description('Resource ID this alert is scoped to (AKS cluster)')
param scopeResourceId string

resource http500Alert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workloadName}-http-500-errors'
  location: location
  tags: tags
  properties: {
    displayName: 'HTTP 500 Errors Detected'
    description: 'Fires when the workshop app logs error responses in container logs — typically caused by CosmosDB connectivity or RBAC failures.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      scopeResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            let workshopContainers = KubePodInventory
            | where Namespace == "workshop"
            | where TimeGenerated > ago(1h)
            | distinct ContainerID;
            ContainerLog
            | where ContainerID in (workshopContainers)
            | where LogEntry has "Failed to read items from CosmosDB" or LogEntry has "RBAC" or LogEntry has "StatusCode: 500" or LogEntry has "Forbidden"
            | summarize ErrorCount = count() by bin(TimeGenerated, 5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}
```

- [ ] **Step 3: Create `query.kql`** (the ContainerLog investigation query; `{{VM_NAME}}` is irrelevant for AKS and intentionally absent)

```kusto
let workshopContainers = KubePodInventory
| where Namespace == "workshop"
| where TimeGenerated > ago(1h)
| distinct ContainerID;
ContainerLog
| where ContainerID in (workshopContainers)
| where LogEntry has "Failed to read items from CosmosDB" or LogEntry has "RBAC" or LogEntry has "Forbidden" or LogEntry has "StatusCode: 500"
| project TimeGenerated, LogEntry
| top 50 by TimeGenerated desc
```

- [ ] **Step 4: Create `inject.sh`** (runtime break: delete the role assignment + restart pods)

```bash
#!/usr/bin/env bash
set -euo pipefail
RESOURCE_GROUP="rg-srelab"
NAMESPACE="workshop"
DEPLOYMENT="web-app"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

COSMOS_ACCOUNT=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
if [ -z "$COSMOS_ACCOUNT" ]; then echo "No CosmosDB account found in $RESOURCE_GROUP" >&2; exit 1; fi

ASSIGNMENT_NAME=$(az cosmosdb sql role assignment list \
  --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv)
if [ -z "$ASSIGNMENT_NAME" ]; then echo "No role assignment to delete (already broken?)"; else
  az cosmosdb sql role assignment delete \
    --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
    --role-assignment-id "$ASSIGNMENT_NAME" --yes
  echo "Deleted role assignment $ASSIGNMENT_NAME on $COSMOS_ACCOUNT"
fi

kubectl rollout restart "deployment/$DEPLOYMENT" -n "$NAMESPACE"
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s
echo "Fault injected: CosmosDB RBAC removed and pods restarted."
```

- [ ] **Step 5: Create `remediate.sh`** (runtime fallback fix: recreate the role assignment + restart pods)

```bash
#!/usr/bin/env bash
set -euo pipefail
RESOURCE_GROUP="rg-srelab"
WORKLOAD="srelab"
NAMESPACE="workshop"
DEPLOYMENT="web-app"
ROLE_DEF_ID="00000000-0000-0000-0000-000000000002"

while [ $# -gt 0 ]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -w|--workload) WORKLOAD="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--resource-group <rg>] [--workload <name>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

COSMOS_ACCOUNT=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
PRINCIPAL_ID=$(az identity show --name "${WORKLOAD}-id" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)

az cosmosdb sql role assignment create \
  --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
  --role-definition-id "$ROLE_DEF_ID" \
  --principal-id "$PRINCIPAL_ID" \
  --scope "/"
echo "Recreated CosmosDB role assignment for ${WORKLOAD}-id on $COSMOS_ACCOUNT"

kubectl rollout restart "deployment/$DEPLOYMENT" -n "$NAMESPACE"
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s
echo "Remediation complete: RBAC restored and pods restarted."
```

- [ ] **Step 6: Create `validate.sh`** (probe `/items`, expect HTTP 200)

```bash
#!/usr/bin/env bash
set -euo pipefail
NAMESPACE="workshop"
SERVICE="web-app"

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--service) SERVICE="$2"; shift 2 ;;
    -N|--namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--service <svc>] [--namespace <ns>]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

APP_IP=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$APP_IP" ]; then echo "No external IP yet for svc/$SERVICE" >&2; exit 1; fi

CODE=$(curl -fsS -o /dev/null -w '%{http_code}' "http://$APP_IP/items" || true)
echo "GET http://$APP_IP/items -> $CODE"
if [ "$CODE" = "200" ]; then echo "Healthy: /items returns 200"; exit 0; fi
echo "Degraded: /items did not return 200" >&2
exit 1
```

- [ ] **Step 7: Create the three PowerShell peers**

`inject.ps1`:
```powershell
#!/usr/bin/env pwsh
param([string]$ResourceGroup = "rg-srelab", [string]$Namespace = "workshop", [string]$Deployment = "web-app")
$ErrorActionPreference = 'Stop'
$cosmos = az cosmosdb list --resource-group $ResourceGroup --query "[0].name" -o tsv
if (-not $cosmos) { throw "No CosmosDB account found in $ResourceGroup" }
$assignment = az cosmosdb sql role assignment list --account-name $cosmos --resource-group $ResourceGroup --query "[0].name" -o tsv
if ($assignment) {
    az cosmosdb sql role assignment delete --account-name $cosmos --resource-group $ResourceGroup --role-assignment-id $assignment --yes
    Write-Host "Deleted role assignment $assignment on $cosmos"
} else { Write-Host "No role assignment to delete (already broken?)" }
kubectl rollout restart "deployment/$Deployment" -n $Namespace
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=90s
Write-Host "Fault injected: CosmosDB RBAC removed and pods restarted."
```

`remediate.ps1`:
```powershell
#!/usr/bin/env pwsh
param([string]$ResourceGroup = "rg-srelab", [string]$Workload = "srelab", [string]$Namespace = "workshop", [string]$Deployment = "web-app")
$ErrorActionPreference = 'Stop'
$roleDefId = "00000000-0000-0000-0000-000000000002"
$cosmos = az cosmosdb list --resource-group $ResourceGroup --query "[0].name" -o tsv
$principalId = az identity show --name "$Workload-id" --resource-group $ResourceGroup --query principalId -o tsv
az cosmosdb sql role assignment create --account-name $cosmos --resource-group $ResourceGroup --role-definition-id $roleDefId --principal-id $principalId --scope "/"
Write-Host "Recreated CosmosDB role assignment for $Workload-id on $cosmos"
kubectl rollout restart "deployment/$Deployment" -n $Namespace
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=90s
Write-Host "Remediation complete: RBAC restored and pods restarted."
```

`validate.ps1`:
```powershell
#!/usr/bin/env pwsh
param([string]$Service = "web-app", [string]$Namespace = "workshop")
$ErrorActionPreference = 'Stop'
$ip = kubectl get svc $Service -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
if (-not $ip) { throw "No external IP yet for svc/$Service" }
try { $resp = Invoke-WebRequest -Uri "http://$ip/items" -UseBasicParsing; $code = $resp.StatusCode }
catch { $code = $_.Exception.Response.StatusCode.value__ }
Write-Host "GET http://$ip/items -> $code"
if ($code -eq 200) { Write-Host "Healthy: /items returns 200"; exit 0 }
Write-Error "Degraded: /items did not return 200"; exit 1
```

- [ ] **Step 8: Mark shell scripts executable and build the alert**

```bash
chmod +x workshops/aks/scenarios/cosmos-rbac-removal/{inject,remediate,validate}.sh
az bicep build --file workshops/aks/scenarios/cosmos-rbac-removal/alert.bicep --stdout > /dev/null && echo "cosmos alert builds"
```
Expected: `cosmos alert builds`.

- [ ] **Step 9: Fix internal links in the moved scenario README** (`workshops/aks/scenarios/cosmos-rbac-removal/README.md`, formerly `docs/05-break-it.md`)

Find references and repoint them:
```bash
grep -nE "06-watch-sre-agent|07-cleanup|0[0-4]-|infra/bicep|\]\(\./" workshops/aks/scenarios/cosmos-rbac-removal/README.md
```
- `docs/06-watch-sre-agent.md` → `../../docs/90-watch-sre-agent.md`
- `docs/07-cleanup.md` → `../../docs/99-cleanup.md`
- `infra/bicep/modules/identity.bicep` → `../../infra/bicep/modules/identity.bicep`
- sibling module links `04-...md` → `../../docs/04-configure-incident-response.md`

- [ ] **Step 10: Commit**

```bash
git add workshops/aks/scenarios/cosmos-rbac-removal
git commit -m "feat(aks): adopt cosmos-rbac-removal as a self-contained scenario"
```

### Task 3.3: Rewire AKS `main.bicep` to the generated aggregator

**Files:**
- Modify: `workshops/aks/infra/bicep/main.bicep` (remove inline `http500Alert`, add `scenarioAlerts` module)
- Generate: `workshops/aks/infra/bicep/modules/scenario-alerts.bicep`

- [ ] **Step 1: Remove the inline `http500Alert`** — delete the comment block + resource (the section beginning `// 6. Alert: HTTP 500 errors in container logs` through the closing `}` of `resource http500Alert ... { ... }`). Leave `restartAlert` untouched.

- [ ] **Step 2: Add a `scenarioAlerts` module call** in its place (right after `restartAlert`)

```bicep
// ──────────────────────────────────────────────
// 6. Per-scenario alerts (generated from workshops/aks/scenarios/*)
// ──────────────────────────────────────────────
module scenarioAlerts 'modules/scenario-alerts.bicep' = {
  name: 'scenario-alerts'
  params: {
    location: location
    workloadName: workloadName
    tags: tags
    clusterId: aks.outputs.clusterId
  }
}
```

- [ ] **Step 3: Generate the AKS aggregator + INDEX**

Run: `scripts/validate-scenarios.sh --write`
Expected: prints `generated aks: 1 scenario(s)` and `generated vm: 3 scenario(s)`; creates `workshops/aks/infra/bicep/modules/scenario-alerts.bicep` (declares `param clusterId string`, one `cosmosRbacRemovalAlert` module) and `workshops/aks/scenarios/INDEX.md`.

- [ ] **Step 4: Build the full AKS template**

Run: `az bicep build --file workshops/aks/infra/bicep/main.bicep --stdout > /dev/null && echo "aks main builds (scenario alerts)"`
Expected: `aks main builds (scenario alerts)`.

- [ ] **Step 5: Validate (no drift)**

Run: `scripts/validate-scenarios.sh`
Expected: `Scenario validation passed`.

- [ ] **Step 6: Commit**

```bash
git add workshops/aks/infra/bicep/main.bicep workshops/aks/infra/bicep/modules/scenario-alerts.bicep workshops/aks/scenarios/INDEX.md
git commit -m "refactor(aks): generate http-500 alert from cosmos-rbac-removal scenario"
```

### Task 3.4: Rename + repath the four AKS workflows

**Files (git mv then edit):**
- `.github/workflows/deploy-infra.yml` → `deploy-aks-infra.yml`
- `.github/workflows/deploy-app.yml` → `deploy-aks-app.yml`
- `.github/workflows/publish-image.yml` → `publish-aks-image.yml`
- `.github/workflows/validate-infra.yml` → `validate-aks-infra.yml`

- [ ] **Step 1: Rename all four**

```bash
git mv .github/workflows/deploy-infra.yml   .github/workflows/deploy-aks-infra.yml
git mv .github/workflows/deploy-app.yml     .github/workflows/deploy-aks-app.yml
git mv .github/workflows/publish-image.yml  .github/workflows/publish-aks-image.yml
git mv .github/workflows/validate-infra.yml .github/workflows/validate-aks-infra.yml
```

- [ ] **Step 2: Edit `deploy-aks-infra.yml`** — display name + template/param paths
  - `name: Deploy Infrastructure` → `name: Deploy AKS Infrastructure`
  - `--template-file infra/bicep/main.bicep` → `--template-file workshops/aks/infra/bicep/main.bicep`
  - `--parameters infra/bicep/main.bicepparam` → `--parameters workshops/aks/infra/bicep/main.bicepparam`

- [ ] **Step 3: Edit `deploy-aks-app.yml`** — display name + the four `k8s/` manifest paths
  - `name: Deploy Application` → `name: Deploy AKS Application`
  - `k8s/namespace.yaml` → `workshops/aks/k8s/namespace.yaml`
  - `k8s/service-account.yaml` → `workshops/aks/k8s/service-account.yaml`
  - `k8s/deployment.yaml` → `workshops/aks/k8s/deployment.yaml`
  - `k8s/service.yaml` → `workshops/aks/k8s/service.yaml`

- [ ] **Step 4: Edit `publish-aks-image.yml`** — trigger path + build context
  - `paths: ['src/**']` → `paths: ['workshops/aks/src/**']`
  - `context: src/app` → `context: workshops/aks/src/app`

- [ ] **Step 5: Edit `validate-aks-infra.yml`** — display name, trigger paths, template/param paths
  - `name: Validate Infrastructure` → `name: Validate AKS Infrastructure`
  - both `paths: ['infra/**']` (push + pull_request) → `paths: ['workshops/aks/infra/**']`
  - both `--file infra/bicep/main.bicep` / `--template-file infra/bicep/main.bicep` → `workshops/aks/infra/bicep/main.bicep`
  - `--parameters infra/bicep/main.bicepparam` → `--parameters workshops/aks/infra/bicep/main.bicepparam`

- [ ] **Step 6: Lint all four workflow YAMLs**

Run:
```bash
cd scripts/scenario-tools && node -e "const fs=require('fs');import('js-yaml').then(y=>{for(const f of ['deploy-aks-infra','deploy-aks-app','publish-aks-image','validate-aks-infra']){y.default.load(fs.readFileSync('../../.github/workflows/'+f+'.yml','utf8'))}console.log('aks workflows YAML OK')})"
```
Expected: `aks workflows YAML OK`.

- [ ] **Step 7: Confirm no stale top-level paths remain in the AKS workflows**

Run:
```bash
grep -nE "(file|parameters|context|paths|-f) .*(^| )(infra|k8s|src)/" .github/workflows/deploy-aks-infra.yml .github/workflows/deploy-aks-app.yml .github/workflows/publish-aks-image.yml .github/workflows/validate-aks-infra.yml || echo "no stale workflow paths"
```
Expected: `no stale workflow paths`.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows
git commit -m "ci(aks): rename and repath AKS workflows to workshops/aks"
```

### Task 3.5: Redirect stubs, AKS track README, and final link sweep

**Files:**
- Create 8 redirect stubs: `docs/00-prerequisites.md`, `docs/01-deploy-infrastructure.md`, `docs/02-deploy-application.md`, `docs/03-onboard-sre-agent.md`, `docs/04-configure-incident-response.md`, `docs/05-break-it.md`, `docs/06-watch-sre-agent.md`, `docs/07-cleanup.md`
- Create: `workshops/aks/README.md`

- [ ] **Step 1: Create the 8 redirect stubs.** Each is a one-line pointer. Contents:

`docs/00-prerequisites.md`:
```markdown
# Moved

This page is now part of the AKS workshop: [workshops/aks/docs/00-prerequisites.md](../workshops/aks/docs/00-prerequisites.md).
```
`docs/01-deploy-infrastructure.md` → `../workshops/aks/docs/01-deploy-infrastructure.md`
`docs/02-deploy-application.md` → `../workshops/aks/docs/02-deploy-application.md`
`docs/03-onboard-sre-agent.md` → `../workshops/aks/docs/03-onboard-sre-agent.md`
`docs/04-configure-incident-response.md` → `../workshops/aks/docs/04-configure-incident-response.md`
`docs/05-break-it.md` → `../workshops/aks/scenarios/cosmos-rbac-removal/README.md`
`docs/06-watch-sre-agent.md` → `../workshops/aks/docs/90-watch-sre-agent.md`
`docs/07-cleanup.md` → `../workshops/aks/docs/99-cleanup.md`

(Use the same `# Moved` template, swapping the link target and label to the path listed above.)

- [ ] **Step 2: Create `workshops/aks/README.md`** with nav + a generated scenario table region

````markdown
# AKS / Cloud-Native SRE Workshop

Deploy AKS + CosmosDB, run a Node.js workload with workload identity, then break and
recover it with the Azure SRE Agent.

## Workshop modules

- [00. Prerequisites](./docs/00-prerequisites.md)
- [01. Deploy Infrastructure](./docs/01-deploy-infrastructure.md)
- [02. Deploy Application](./docs/02-deploy-application.md)
- [03. Onboard SRE Agent](./docs/03-onboard-sre-agent.md)
- [04. Configure Incident Response](./docs/04-configure-incident-response.md)
- [90. Watch SRE Agent](./docs/90-watch-sre-agent.md)
- [99. Cleanup](./docs/99-cleanup.md)

## Scenarios

<!-- BEGIN SCENARIOS -->
<!-- END SCENARIOS -->
````

- [ ] **Step 3: Generate the AKS README table + INDEX**

Run: `scripts/validate-scenarios.sh --write`
Expected: the AKS README now has a one-row scenario table between the markers; `Scenario validation passed` when re-validated.

- [ ] **Step 4: Repository-wide stale-link sweep** (catch any doc still pointing at old top-level locations; the root `README.md` is intentionally deferred to Phase 4)

Run:
```bash
grep -rnE "\]\((\.\./)*(infra|k8s|src)/bicep|docs/0[1-7]-|docs/00-prerequisites" workshops CONTRIBUTING.md 2>/dev/null || echo "no stale links in workshops"
```
Fix any hit found inside `workshops/**` to use the relocated path.

- [ ] **Step 5: Verify the working tree is coherent**

Run:
```bash
az bicep build --file workshops/aks/infra/bicep/main.bicep --stdout > /dev/null \
  && scripts/validate-scenarios.sh \
  && cd scripts/scenario-tools && npm test
```
Expected: AKS template builds, `Scenario validation passed`, all unit tests pass.

- [ ] **Step 6: Commit**

```bash
git add docs workshops/aks/README.md workshops/aks/scenarios/INDEX.md
git commit -m "docs(aks): add redirect stubs and AKS track README"
```

**Phase 3 complete:** both tracks live under `workshops/<track>/`, both expose scenarios through identical structure, all alerts are generated, and old documentation links still resolve via stubs.

## Phase 4 — Shared Concept Layer & Contributor Docs (low risk, mostly prose)

Repurposes the now-thin top-level `docs/` into the **shared concept layer**, rewrites the two landing pages as a portfolio + track index, and adds a full `CONTRIBUTING.md`. The three concept docs are delivered as **structured starter outlines** (headings, key points, links) for the maintainer to expand with their own voice — they are not ghostwritten. `CONTRIBUTING.md` and the landing-page skeletons are delivered in full.

> The Phase 3 redirect stubs (`docs/00-prerequisites.md` … `docs/07-cleanup.md`) coexist with the new concept docs (`docs/00-what-is-sre-agent.md`, `01-why-sre-agent.md`, `02-how-it-works.md`); the filenames differ. Treat the stubs as migration aids removable once external links are updated.

### Task 4.1: Shared concept docs (starter outlines)

**Files:**
- Create: `docs/00-what-is-sre-agent.md`, `docs/01-why-sre-agent.md`, `docs/02-how-it-works.md`

- [ ] **Step 1: Create `docs/00-what-is-sre-agent.md`**

````markdown
# What is the Azure SRE Agent?

> Shared concept (track-agnostic). Watched by the docs-freshness workflow.

## In one sentence

<!-- One-paragraph definition: an AI agent that detects, diagnoses, and helps remediate
     production incidents on Azure, integrating with GitHub for code-level fixes. -->

## What it is / what it is not

- It is: <!-- autonomous-but-supervised incident responder, telemetry-aware, GitOps-native -->
- It is not: <!-- a replacement for on-call judgment; a silent auto-changer of infra -->

## Where it runs

<!-- sre.azure.com portal; connects to Azure resources + a GitHub repo -->

## Key concepts referenced elsewhere in this repo

- Operational guidelines → [`docs/knowledge/operational-guidelines.md`](./knowledge/operational-guidelines.md)
- Why it matters → [01-why-sre-agent.md](./01-why-sre-agent.md)
- How the loop works → [02-how-it-works.md](./02-how-it-works.md)

## Upstream references

<!-- Link the canonical learn.microsoft.com/azure/sre-agent pages here. -->
````

- [ ] **Step 2: Create `docs/01-why-sre-agent.md`**

````markdown
# Why use the Azure SRE Agent?

> Shared concept (track-agnostic). Watched by the docs-freshness workflow.

## The problem it addresses

<!-- MTTR, alert fatigue, tribal knowledge, 3am pages, inconsistent remediation. -->

## The value

- Faster detection → diagnosis → fix (MTTR reduction)
- Consistent, auditable remediation (vs ad-hoc manual fixes)
- Knowledge captured as code (issues, PRs, guidelines)

## When it shines (and when it doesn't)

<!-- Good: well-instrumented, GitOps-managed workloads. Limited: undocumented, manual envs. -->

## How this workshop demonstrates the value

- AKS track → [cosmos-rbac-removal scenario](../workshops/aks/scenarios/cosmos-rbac-removal/README.md)
- VM track → [scenario index](../workshops/vm/scenarios/INDEX.md)

## Upstream references

<!-- Link any official ROI/positioning material. -->
````

- [ ] **Step 3: Create `docs/02-how-it-works.md`**

````markdown
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
````

- [ ] **Step 4: Commit**

```bash
git add docs/00-what-is-sre-agent.md docs/01-why-sre-agent.md docs/02-how-it-works.md
git commit -m "docs: add shared SRE Agent concept layer (starter outlines)"
```

### Task 4.2: Rewrite the root `README.md` as a portfolio landing

**Files:**
- Modify: `README.md` (restructure to: vision → concept layer → track index → quick start → contributing)

- [ ] **Step 1: Replace the AKS-centric body** with a track-portfolio structure. Keep the top title/tagline; replace the "What You'll Learn / Architecture / Workshop Tracks / AKS Workshop Modules" sections with:

````markdown
## Start here

New to the Azure SRE Agent? Read the shared concept layer first:

1. [What is the SRE Agent?](docs/00-what-is-sre-agent.md)
2. [Why use it?](docs/01-why-sre-agent.md)
3. [How it works](docs/02-how-it-works.md)

## Choose a track

| Track | Focus | Start |
| --- | --- | --- |
| **AKS / Cloud-Native** | Kubernetes workload identity, CosmosDB RBAC fault injection | [workshops/aks/](workshops/aks/README.md) |
| **VM / Enterprise Migration** | Windows Server + IIS, Bastion access, approval-gated remediation | [workshops/vm/](workshops/vm/README.md) |

Each track follows the same loop: **deploy from code → inject a realistic fault →
watch the agent investigate → apply controlled remediation → capture a postmortem.**

## Scenarios at a glance

- AKS scenarios: [workshops/aks/scenarios/INDEX.md](workshops/aks/scenarios/INDEX.md)
- VM scenarios: [workshops/vm/scenarios/INDEX.md](workshops/vm/scenarios/INDEX.md)

## Contributing a scenario

This repo is built to grow. See [CONTRIBUTING.md](CONTRIBUTING.md) to add a new scenario
(one self-contained folder) or a whole new track.
````

Preserve the existing **Cost Estimate**, prerequisites callouts, and license/footer sections; only the AKS-specific module table and architecture diagram move conceptually under the AKS track (they already exist in `workshops/aks/docs/`).

- [ ] **Step 2: Fix the footer "Ready to begin" link** (line ~238) from `docs/00-prerequisites.md` to `workshops/aks/docs/00-prerequisites.md` (or to the new `docs/00-what-is-sre-agent.md` concept entry).

- [ ] **Step 3: Verify no root README links point at moved-away top-level paths**

Run: `grep -nE "\]\(docs/0[0-7]-(prereq|deploy|onboard|configure|break|watch|cleanup)" README.md || echo "root README links clean"`
Expected: `root README links clean` (any remaining setup-doc links should target `workshops/aks/...`).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: restructure root README as track portfolio landing"
```

### Task 4.3: Refresh `workshops/README.md` (track index)

**Files:**
- Modify: `workshops/README.md`

- [ ] **Step 1: Add a scenario-count-aware track index** below the existing "Tracks" list

Append after the current `- [VM Workshop](./vm/README.md)` line:
```markdown

## Scenario indexes

- [AKS scenarios](./aks/scenarios/INDEX.md)
- [VM scenarios](./vm/scenarios/INDEX.md)

## Adding a scenario

Run `scripts/new-scenario.sh <track> <id> "<Title>"` from the repo root, then follow the
printed checklist. See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full flow.
```

- [ ] **Step 2: Commit**

```bash
git add workshops/README.md
git commit -m "docs: link scenario indexes from workshops landing"
```

### Task 4.4: `CONTRIBUTING.md` (full content)

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Create `CONTRIBUTING.md`** (delivered in full — this is the contributor contract)

`````markdown
# Contributing

Thanks for extending the SRE Agent Workshop! The most common contribution is **a new
scenario**. Scenarios are self-contained folders governed by a manifest contract, so adding
one requires **no edits to shared infrastructure or tooling**.

## Prerequisites

- Node.js 22+ (for the scenario tooling under `scripts/scenario-tools/`)
- Azure CLI with Bicep (`az bicep version`)
- PowerShell 7+ if you want to run the `.ps1` script variants

## Add a scenario (the 6-step flow)

1. **Scaffold** from the canonical template:

   ```bash
   scripts/new-scenario.sh <track> <scenario-id> "Human Title"
   # e.g. scripts/new-scenario.sh vm memory-leak "Memory Leak"
   ```

   `<track>` is `aks` or `vm`; `<scenario-id>` is kebab-case and becomes the folder name.

2. **Fill in `scenario.yaml`.** Required: `id` (== folder name), `title`, `track`,
   `summary`, `severity` (0–4), `inject`, `validate`, `docPage`. Recommended: `estimatedMinutes`,
   `difficulty`, `learningObjectives`, `signal`, `remediate`, `investigation`. The full
   contract lives in [`schemas/scenario.schema.json`](schemas/scenario.schema.json).

3. **Implement the scripts** — both `.sh` and `.ps1` for `inject`, `validate`, and each
   `remediate` action. Keep each remediation script named after its `action` (the VM approval
   gate resolves actions by globbing `scenarios/*/<action>.sh`, so action names are unique
   per track).

4. **Author `alert.bicep` and `query.kql`.** `alert.bicep` must declare exactly
   `location`, `workloadName`, `tags`, and `scopeResourceId`, and bind `scopes: [scopeResourceId]`.
   The generator wires it into the track aggregator automatically. If your scenario needs no
   alert, drop `signal` from the manifest and delete `alert.bicep`.

5. **Write `README.md`** — the attendee walkthrough (inject → observe → investigate →
   remediate → validate).

6. **Generate + validate**:

   ```bash
   scripts/validate-scenarios.sh --write   # regenerates INDEX.md, aggregator, README table
   scripts/validate-scenarios.sh           # must print "Scenario validation passed"
   chmod +x workshops/<track>/scenarios/<id>/*.sh
   ```

Open a PR. CI (`validate-scenarios.yml`) re-runs the schema check, unit tests, drift check,
and `az bicep build` on every `alert.bicep` + aggregator.

## What CI enforces

- `scenario.yaml` validates against the schema.
- `id` == folder name; `track` == parent track directory.
- Required files exist; `.sh` scripts are executable; both `.sh` and `.ps1` exist for
  `inject` / `validate` / each `remediate` action.
- Every `alert.bicep` is wired into the generated `scenario-alerts.bicep`.
- `INDEX.md` and the README scenario table are regenerated and unchanged (no drift).
- Remediation action names are unique within a track.

## Add a track (advanced)

Tracks are the closed set in `scripts/scenario-tools/lib/paths.js` (`TRACKS`). To add one
(e.g. `appservice`):

1. Add an entry to `TRACKS` with its alert `scopeParam` (the Bicep param name the aggregator
   passes into each scenario's `scopeResourceId`, e.g. an App Service resource ID).
2. Create `workshops/<track>/` with `README.md` (include the
   `<!-- BEGIN SCENARIOS -->` / `<!-- END SCENARIOS -->` markers), `docs/`, `infra/bicep/`,
   and `scenarios/`.
3. If the track deploys alerts, have `infra/bicep/main.bicep` call the generated
   `modules/scenario-alerts.bicep` with the track's scope resource ID.
4. Add the track's enum value to `schemas/scenario.schema.json` (`properties.track.enum`).
5. Add a workflow `validate-<track>-infra.yml` mirroring the existing ones, repathed to
   `workshops/<track>/infra/**`.
6. Scaffold a first scenario and run `scripts/validate-scenarios.sh --write`.

## Style

- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `test:`).
- Keep scenarios self-contained: prefer adding files under `scenarios/<id>/` over editing
  shared tooling.
`````

- [ ] **Step 2: Sanity-check the schema/track references in CONTRIBUTING are accurate**

Run: `grep -n "enum\|scopeParam\|TRACKS" schemas/scenario.schema.json scripts/scenario-tools/lib/paths.js`
Expected: confirms `track.enum` is `[aks, vm]` and `TRACKS` has matching keys with `scopeParam`.

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING guide for scenarios and tracks"
```

**Phase 4 complete:** shared concept layer exists, both landing pages point into the track/scenario structure, and contributors have a complete self-service guide.

## Phase 5 — Docs-Freshness Agentic Workflow (low risk, independent)

Adds a weekly `gh-aw` workflow that compares the shared concept layer against upstream Azure
SRE Agent docs and opens a **draft** PR when something drifts. Independent of Phases 1–4
(only depends on the concept docs existing from Phase 4). Distinct from the `.squad/*` system.

### Task 5.1: Author the agentic workflow source

**Files:**
- Create: `.github/workflows/sre-docs-freshness.md`

- [ ] **Step 1: Create `.github/workflows/sre-docs-freshness.md`** (front-matter config + natural-language body, per the approved spec)

`````markdown
---
name: SRE Agent Docs Freshness
on:
  schedule:
    - cron: "0 7 * * 1"   # Mondays 07:00 UTC
  workflow_dispatch:
engine: copilot
permissions:
  contents: read
network:
  allowed:
    - defaults
    - learn.microsoft.com
    - "*.azure.com"
tools:
  web-fetch:
  bash: ["git"]
safe-outputs:
  create-pull-request:
    title-prefix: "[docs-freshness] "
    labels: [documentation, automated]
    draft: true
---

# SRE Agent Docs Freshness

You keep this repository's **shared concept layer** aligned with upstream Azure SRE Agent
documentation. You never change docs silently — you open a single draft PR for human review.

## Scope (read these, and only edit these)

- `docs/00-what-is-sre-agent.md`
- `docs/01-why-sre-agent.md`
- `docs/02-how-it-works.md`
- `docs/knowledge/operational-guidelines.md`

Do **not** touch track setup docs or scenario walkthroughs — those describe this repo's own
code, not upstream behavior.

## Upstream sources

Fetch the current Azure SRE Agent documentation under `learn.microsoft.com` (the SRE Agent
overview, how-it-works, and autonomy/configuration pages).

## Task

1. For each in-scope file, compare its claims against the upstream sources.
2. If something is outdated, renamed, or removed upstream — or a notable new capability now
   exists — make the **minimal** edits needed to correct the affected file(s).
3. Open **one** draft PR summarizing what changed upstream, with cited source URLs.
4. If everything is already current, do nothing (no PR).
`````

- [ ] **Step 2: Commit the source** (the compiled lock file is added in Task 5.2)

```bash
git add .github/workflows/sre-docs-freshness.md
git commit -m "ci: add weekly SRE Agent docs-freshness agentic workflow"
```

### Task 5.2: Compile with `gh-aw`

**Files:**
- Create: `.github/workflows/sre-docs-freshness.lock.yml` (generated by `gh aw compile`)

- [ ] **Step 1: Install the `gh-aw` extension** (requires `gh` auth + network)

Run: `gh extension install githubnext/gh-aw`
Expected: installs the `aw` subcommand. (If already installed: `gh extension upgrade gh-aw`.)

- [ ] **Step 2: Compile the workflow**

Run: `gh aw compile`
Expected: produces `.github/workflows/sre-docs-freshness.lock.yml` from the `.md` source; exit 0.
> If `gh aw compile` is unavailable in this environment, note it in the PR and have a maintainer run it; the `.md` source is the source of truth and must always be committed alongside its `.lock.yml`.

- [ ] **Step 3: Sanity-check the generated lock file is valid YAML**

Run:
```bash
cd scripts/scenario-tools && node -e "const fs=require('fs');import('js-yaml').then(y=>{y.default.load(fs.readFileSync('../../.github/workflows/sre-docs-freshness.lock.yml','utf8'));console.log('lock YAML OK')})"
```
Expected: `lock YAML OK`.

- [ ] **Step 4: Commit both files together**

```bash
git add .github/workflows/sre-docs-freshness.md .github/workflows/sre-docs-freshness.lock.yml
git commit -m "ci: compile docs-freshness workflow lock file"
```

### Task 5.3: Mark compiled lock files as generated

**Files:**
- Modify: `.gitattributes`

- [ ] **Step 1: Append the lock-file attributes** to `.gitattributes` (keep the existing `.squad` block)

```
# gh-aw: compiled agentic workflow lock files are generated artifacts
.github/workflows/*.lock.yml linguist-generated=true merge=ours
```

- [ ] **Step 2: Verify the attribute applies**

Run: `git check-attr linguist-generated merge -- .github/workflows/sre-docs-freshness.lock.yml`
Expected: shows `linguist-generated: true` and `merge: ours`.

- [ ] **Step 3: Commit**

```bash
git add .gitattributes
git commit -m "chore: treat gh-aw lock files as generated"
```

**Phase 5 complete:** a weekly, draft-only docs-freshness agent watches the shared concept
layer, with its compiled artifact tracked and marked generated.

---

## Final Verification (run after all phases)

- [ ] **Full tooling test suite**

Run: `cd scripts/scenario-tools && npm test`
Expected: all tests pass across `validate.test.js`, `generate.test.js`, `template.test.js`.

- [ ] **Scenario validation (schema + drift across both tracks)**

Run: `scripts/validate-scenarios.sh`
Expected: `Scenario validation passed`.

- [ ] **Every scenario + aggregator Bicep builds**

Run:
```bash
for f in workshops/*/scenarios/*/alert.bicep workshops/*/infra/bicep/modules/scenario-alerts.bicep workshops/*/infra/bicep/main.bicep; do
  echo "Building $f"; az bicep build --file "$f" --stdout > /dev/null || { echo "FAILED: $f"; break; }
done
echo "all bicep built"
```
Expected: each file builds; ends with `all bicep built`.

- [ ] **No stale top-level directories remain**

Run: `ls -d infra k8s src 2>/dev/null && echo "STALE DIRS PRESENT" || echo "top-level relocated cleanly"`
Expected: `top-level relocated cleanly`.

- [ ] **Workflow inventory is correct**

Run: `ls .github/workflows/ | grep -E "aks|vm|scenarios|docs-freshness"`
Expected: `deploy-aks-infra.yml`, `deploy-aks-app.yml`, `publish-aks-image.yml`, `validate-aks-infra.yml`, `deploy-vm-infra.yml`, `validate-vm-infra.yml`, `validate-scenarios.yml`, `sre-docs-freshness.md`, `sre-docs-freshness.lock.yml` (the `.squad/*` workflows are unchanged).

---

## Self-Review Notes (deviations & coverage)

- **Single shared template vs per-track `_template/`.** The spec diagram (§4) shows a
  `_template/` under each track's `scenarios/`. This plan instead keeps one canonical template
  at `scripts/scenario-tools/template/` (DRY — one place to maintain). Scenario discovery
  (`scenarioDirs`) still skips any `_`-prefixed folder, so a per-track `_template/` would be
  ignored if a contributor adds one. This is an intentional refinement consistent with §6
  ("`new-scenario.sh` copies `_template/`") — the template is just sourced from the tooling.
- **Approval-gate rewrite (Task 2.6) is an addition beyond the spec's §5.2**, which only
  called out the *investigation* tool. Moving remediation scripts into scenario folders
  breaks `invoke-approved-remediation.{sh,ps1}`; the glob-based rewrite + per-track action
  uniqueness keeps the manifests as the single source of truth. Captured here so it is not
  mistaken for scope creep.
- **`publish-image.yml` uses `GITHUB_TOKEN`/GHCR, not `AZURE_CREDENTIALS`** (the older
  copilot-instructions note is stale); Task 3.4 only repaths it, preserving the image name
  `ghcr.io/<owner>/sre-agent-workshop/app`.
- **Spec coverage map:** §5 contract → Phase 1 (schema/tooling/template) + Tasks 2.1–2.3,
  3.2; §5.2 scattering points → Tasks 2.4–2.6, 3.3 (alerts), 2.5 (investigation), generators
  (INDEX/README); §4 structure/relocation → Phase 3; §6 contributor/CI → Tasks 1.11, 4.4;
  §7 docs-freshness → Phase 5; concept layer (§4 Layer 1) → Task 4.1.


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

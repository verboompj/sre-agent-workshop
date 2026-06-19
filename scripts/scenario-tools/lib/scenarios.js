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

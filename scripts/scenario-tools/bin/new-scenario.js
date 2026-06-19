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

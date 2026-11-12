#!/usr/bin/env node
// Re-clone registered projects whose checkout is missing (e.g. after cloning the workspace on a new machine).
// Node twin of tools/projects-restore.sh (same output).
// Reads `name:`, `remote:`, `branch:` and `status:` from each projects/ws_<name>.md card.
// Usage: node tools/projects-restore.mjs [name ...]    (no args = all cards; status: archived is skipped)
// Then re-links every project skill (tools/project-skill-link.mjs).
import { ws, run, cardField, isDir, isFile, ls } from './_lib.mjs';
import { linkProjectSkills } from './project-skill-link.mjs';

const names = process.argv.slice(2);
const cards = names.length
  ? names.map((n) => `projects/ws_${n}.md`)
  : ls(`${ws}/projects`, /^ws_.*\.md$/).filter((f) => !f.endsWith('.skill.md')).map((f) => `projects/${f}`);

for (const card of cards) {
  const file = `${ws}/${card}`;
  if (!isFile(file)) { console.error(`no card: ${card}`); continue; }
  const [name, remote, branch, status] = ['name', 'remote', 'branch', 'status'].map((k) => cardField(file, k));
  const dir = `projects/${name}`;
  if (isDir(`${ws}/${dir}/.git`)) { console.log(`ok       ${name}`); continue; }
  if (status === 'archived' && !names.length) { console.log(`skip     ${name} (archived)`); continue; }
  if (!remote || remote === '?') { console.error(`NO REMOTE ${name} — fix card`); continue; }
  console.log(`clone    ${name} ← ${remote}${branch ? ` (${branch})` : ''}`);
  const args = ['clone', '-q', ...(branch ? ['--branch', branch] : []), remote, dir];
  if (run('git', args, { cwd: ws }).code !== 0) console.error(`FAILED   ${name}`);
}

// project skills (tracked projects/ws_*.skill.md → ignored skills/ws-project-*/SKILL.md)
linkProjectSkills();

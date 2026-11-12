#!/usr/bin/env node
// Mechanical workspace lint. Node twin of tools/wiki-lint.sh (same checks, same output).
// Usage: node tools/wiki-lint.mjs   (run from anywhere)   exit 0 = clean
import fs from 'node:fs';
import path from 'node:path';
import { ws, readText, lines, ls, walk, isDir, isFile } from './_lib.mjs';

process.chdir(ws);
const byCode = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const uniq = (a) => [...new Set(a)].sort(byCode);
const isMd = (name) => name.endsWith('.md');
const WIKI_DIRS = ['wiki/sources', 'wiki/decisions', 'wiki/entities', 'wiki/concepts', 'wiki/notes'];
const projectMd = ls('projects', /\.md$/).map((f) => `projects/${f}`);

// wiki pages (excluding raw/ and index)
const pages = walk('wiki', (name) => isMd(name) && name !== 'index.md', 'wiki/raw');
const slugs = uniq(pages.map((p) => path.basename(p, '.md')));

// link targets in wiki + project cards (skills hold placeholder examples, skip)
// inline `code` spans are stripped so documented placeholders don't count as links
function links(roots) {
  const found = [];
  for (const f of roots.flatMap((r) => walk(r, isMd))) {
    for (const line of lines(readText(f))) {
      for (const m of line.replace(/`[^`]*`/g, '').matchAll(/\[\[([^\]|#]+)/g)) found.push(m[1]);
    }
  }
  return uniq(found);
}
const linked = links([...WIKI_DIRS, 'wiki/index.md', ...projectMd]);
const indexed = new Set(links(['wiki/index.md']));
const slugSet = new Set(slugs);

let rc = 0;
function report(title, items) {
  if (!items.length) return;
  console.log(`## ${title}`);
  for (const i of items) console.log(`- ${i}`);
  rc = 1;
}

report('Broken links (target page missing)', linked.filter((l) => !slugSet.has(l)));
report('Pages missing from wiki/index.md', slugs.filter((s) => !indexed.has(s)));

// orphans: no `[[slug` anywhere outside the indexes
const notIndex = (name) => isMd(name) && name !== 'index.md';
const corpus = [...WIKI_DIRS, ...projectMd].flatMap((r) => walk(r, notIndex)).map((f) => readText(f) ?? '').join('\n');
report('Orphans (no inbound links besides index)', slugs.filter((s) => !corpus.includes(`[[${s}`)));

const skillsIndex = readText('skills/index.md') ?? '';
const skillDirs = ls('skills').filter((n) => isDir(`skills/${n}`));
report('Skills missing from skills/index.md',
  skillDirs.filter((n) => !n.startsWith('ws-project-') && !skillsIndex.includes(`(${n}/SKILL.md)`)));

// project skills: tracked source must be exposed, card must point at it (fix: tools/project-skill-link.mjs)
const pskills = [];
const same = (a, b) => { try { return fs.readFileSync(a).equals(fs.readFileSync(b)); } catch { return false; } };
for (const f of ls('projects', /^ws_.*\.skill\.md$/)) {
  const n = f.slice(3, -'.skill.md'.length);
  const src = `projects/${f}`;
  if (!same(src, `skills/ws-project-${n}/SKILL.md`)) pskills.push(`${src} → skills/ws-project-${n}/SKILL.md missing or stale`);
  const card = lines(readText(`projects/ws_${n}.md`));
  if (!card.some((l) => l.replace(/^skill: */, '\0').startsWith(`\0ws-project-${n}`))) {
    pskills.push(`projects/ws_${n}.md lacks 'skill: ws-project-${n}'`);
  }
}
for (const d of skillDirs.filter((x) => x.startsWith('ws-project-'))) {
  const n = d.slice('ws-project-'.length);
  if (!isFile(`projects/ws_${n}.skill.md`)) pskills.push(`skills/${d}/ has no source projects/ws_${n}.skill.md`);
}
report('Project skills out of sync', pskills);

const projectsIndex = readText('projects/index.md') ?? '';
report('Project cards missing from projects/index.md',
  ls('projects', /^ws_.*\.md$/).filter((n) => !n.endsWith('.skill.md') && !projectsIndex.includes(`(${n})`)));

const workIndex = readText('work/index.md') ?? '';
const tasks = [];
for (const p of ls('work').filter((n) => isDir(`work/${n}`))) {
  for (const t of ls(`work/${p}`).filter((n) => isDir(`work/${p}/${n}`))) {
    if (!workIndex.includes(`(${p}/${t}/)`)) tasks.push(`${p}/${t}`);
  }
}
report('Task dirs missing from work/index.md', tasks);

report('Pages without frontmatter or TL;DR', pages.filter((f) => {
  const l = lines(readText(f));
  return !(l[0] === '---' && l.some((x) => x.startsWith('**TL;DR:**')));
}));

// every tool exists as a pair: tools/<name>.sh (bash fallback) + tools/<name>.mjs (node)
const sh = new Set(ls('tools', /\.sh$/).map((f) => f.slice(0, -3)));
const mjs = new Set(ls('tools', /\.mjs$/).map((f) => f.slice(0, -4)).filter((n) => !n.startsWith('_')));
report('Tools without a .sh/.mjs twin', [
  ...[...sh].filter((n) => !mjs.has(n)).map((n) => `tools/${n}.sh has no tools/${n}.mjs`),
  ...[...mjs].filter((n) => !sh.has(n)).map((n) => `tools/${n}.mjs has no tools/${n}.sh`),
]);

if (rc === 0) console.log('lint: clean');
process.exit(rc);

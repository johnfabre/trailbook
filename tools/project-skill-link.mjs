#!/usr/bin/env node
// Expose tracked project skills to the harness. Node twin of tools/project-skill-link.sh (same output).
// Source (tracked):  projects/ws_<name>.skill.md
// Loaded (ignored):  skills/ws-project-<name>/SKILL.md  → symlink to the source (copy if symlinks unsupported,
//                    e.g. Windows without Developer Mode)
// Usage: node tools/project-skill-link.mjs [name ...]   (no args = every projects/ws_*.skill.md)
// Idempotent; called by onboard-project and tools/projects-restore.mjs.
import fs from 'node:fs';
import { ws, isMain, isFile, ls, slashes } from './_lib.mjs';

export function linkProjectSkills(names = []) {
  const srcs = names.length
    ? names.map((n) => `projects/ws_${n}.skill.md`)
    : ls(`${ws}/projects`, /^ws_.*\.skill\.md$/).map((f) => `projects/${f}`);

  for (const src of srcs) {
    if (!isFile(`${ws}/${src}`)) { console.error(`no source: ${src}`); continue; }
    const n = src.replace(/^projects\/ws_/, '').replace(/\.skill\.md$/, '');
    const dir = `${ws}/skills/ws-project-${n}`;
    const dst = `${dir}/SKILL.md`;
    const rel = `../../${src}`;
    fs.mkdirSync(dir, { recursive: true });
    let cur = null;
    try { cur = slashes(fs.readlinkSync(dst)); } catch { /* not a link */ }
    if (cur === rel) { console.log(`ok       ws-project-${n}`); continue; }
    fs.rmSync(dst, { force: true });
    let linked = false;
    try { fs.symlinkSync(rel, dst, 'file'); linked = isFile(dst); } catch { /* unsupported */ }
    if (linked) console.log(`linked   ws-project-${n}`);
    else {
      fs.rmSync(dst, { force: true });
      fs.copyFileSync(`${ws}/${src}`, dst);
      console.log(`copied   ws-project-${n} (symlink unsupported — rerun after editing source)`);
    }
  }
}

if (isMain(import.meta.url)) linkProjectSkills(process.argv.slice(2));

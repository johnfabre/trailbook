// Shared helpers for the tools/*.mjs scripts. Zero dependencies: Node >= 18 built-ins only.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';

/** Workspace root (parent of tools/), absolute. */
export const ws = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Forward-slash form of a path (what git and the markdown files use). */
export const slashes = (p) => String(p).replace(/\\/g, '/');

/**
 * Run a command without a shell. → { code, out, err }  (code 127 when the binary is missing).
 * opts.quiet hides stderr (the `2>/dev/null` of the bash twins); otherwise stderr goes to the terminal.
 */
export function run(cmd, args, opts = {}) {
  const { quiet, ...rest } = opts;
  const r = spawnSync(cmd, args, {
    encoding: 'utf8', maxBuffer: 1 << 30, windowsHide: true,
    stdio: ['ignore', 'pipe', quiet ? 'ignore' : 'inherit'], ...rest,
  });
  return { code: r.error ? 127 : (r.status ?? 1), out: r.stdout || '', err: r.stderr || '' };
}

/** True when the module at `metaUrl` is the script node was started with (not an import). */
export function isMain(metaUrl) {
  if (!process.argv[1]) return false;
  const norm = (p) => {
    let r = path.resolve(p);
    try { r = fs.realpathSync(r); } catch { /* keep as is */ }
    return process.platform === 'win32' ? r.toLowerCase() : r;
  };
  return norm(process.argv[1]) === norm(fileURLToPath(metaUrl));
}

export function readText(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return null; }
}

export const lines = (text) => (text ? text.split(/\r?\n/) : []);

/** Value of `key:` in a card's frontmatter (between `---` lines), trailing `# comment` stripped. '' if absent. */
export function cardField(card, key) {
  let inside = false;
  for (const line of lines(readText(card))) {
    if (line === '---') { inside = !inside; continue; }
    if (inside && line.startsWith(`${key}:`)) {
      return line.slice(key.length + 1).replace(/^\s+/, '').replace(/\s*#.*$/, '');
    }
  }
  return '';
}

/** Names in `dir` matching `re`, sorted; [] if the directory is missing. */
export function ls(dir, re = /./) {
  try { return fs.readdirSync(dir).filter((n) => re.test(n)).sort(); } catch { return []; }
}

export const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
export const isFile = (p) => { try { return fs.statSync(p).isFile(); } catch { return false; } };

/** Every file under `dir` (recursive, sorted, forward slashes) accepted by `keep`; `skipDir` prunes a path. */
export function walk(dir, keep = () => true, skipDir = null) {
  const out = [];
  const rec = (d) => {
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of ents.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
      const p = `${d}/${e.name}`;
      if (e.isDirectory() || (e.isSymbolicLink() && isDir(p))) { if (p !== skipDir) rec(p); }
      else if (keep(e.name, p)) out.push(p);
    }
  };
  if (isFile(dir)) { if (keep(path.basename(dir), dir)) out.push(slashes(dir)); } else rec(slashes(dir));
  return out;
}

const pad = (n, w = 2) => String(n).padStart(w, '0');
/** Local date `YYYY-MM-DD`. */
export function today(d = new Date()) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
/** Local timestamp `YYYY-MM-DD-HHMMSS`. */
export function stamp(d = new Date()) {
  return `${today(d)}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

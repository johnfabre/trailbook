#!/usr/bin/env node
// Mechanical size/risk gate for the trivial-change path. Run AFTER the main agent's edit, before review.
// Node twin of tools/trivial-gate.sh (same output).
// Usage: node tools/trivial-gate.mjs <repo-path> [max-files=2] [max-lines=20]
// Counts the working tree vs HEAD (tracked + untracked, nothing staged or changed).
// Last lines of output (read only these):
//   STATUS: OK | PROMOTE
//   REASONS: <semicolon list, or ->
//   DIFF: <files> files, <lines> lines
import fs from 'node:fs';
import { run } from './_lib.mjs';

const [repo, maxFilesArg, maxLinesArg] = process.argv.slice(2);
if (!repo) { console.error('usage: trivial-gate.mjs <repo-path> [max-files=2] [max-lines=20]'); process.exit(1); }
const maxFiles = Number(maxFilesArg ?? 2);
const maxLines = Number(maxLinesArg ?? 20);
// Paths that are never trivial, whatever the size (schema, API contracts, auth, money, deps, CI, infra).
const risky = /(migrat|schema|openapi|swagger|\.proto$|\.graphql$|\.sql$|auth|security|permission|payment|billing|secret|\.env|package-lock\.json$|yarn\.lock$|pnpm-lock\.yaml$|Cargo\.lock$|go\.sum$|poetry\.lock$|\.github\/workflows\/|Dockerfile|docker-compose|terraform|\.tf$)/i;

const git = (...a) => run('git', ['-C', repo, ...a], { quiet: true });

if (git('rev-parse', '--verify', '-q', 'HEAD').code !== 0) {
  console.log(`STATUS: PROMOTE\nREASONS: no HEAD in ${repo}\nDIFF: ?`);
  process.exit(0);
}

// Tracked changes vs HEAD, plus untracked files (counted as all-added), without touching the index.
const rows = [];   // [added, deleted, path]  ('-' = binary)
for (const line of git('diff', 'HEAD', '--numstat').out.split('\n')) {
  const m = /^([^\t]*)\t([^\t]*)\t(.+)$/.exec(line);
  if (m) rows.push([m[1], m[2], m[3]]);
}
for (const f of git('ls-files', '--others', '--exclude-standard', '-z').out.split('\0')) {
  if (!f) continue;
  let buf;
  try { buf = fs.readFileSync(`${repo}/${f}`); } catch { rows.push(['-', '-', f]); continue; }
  if (buf.includes(0)) { rows.push(['-', '-', f]); continue; }
  let n = 0;
  for (const b of buf) if (b === 10) n++;
  rows.push([String(n), '0', f]);
}

const reasons = [];
let files = 0;
let total = 0;
for (const [add, del, p] of rows) {
  files++;
  if (add === '-') { reasons.push(`binary: ${p}`); continue; }
  total += Number(add) + Number(del);
  if (risky.test(p)) reasons.push(`risky path: ${p}`);
}
if (files === 0) reasons.push('empty diff');
if (files > maxFiles) reasons.push(`files ${files} > ${maxFiles}`);
if (total > maxLines) reasons.push(`lines ${total} > ${maxLines}`);

console.log(reasons.length ? `STATUS: PROMOTE\nREASONS: ${reasons.join(';')}` : 'STATUS: OK\nREASONS: -');
console.log(`DIFF: ${files} files, ${total} lines`);

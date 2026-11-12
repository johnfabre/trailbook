#!/usr/bin/env node
// Put a project repo on its default branch, pulled to the latest origin — without losing anything.
// Node twin of tools/checkout-base.sh (same steps, same output).
//
// Fast path: tree clean, no git operation in progress → fetch, switch <base>, pull --ff-only.
// Otherwise RESCUE, in this order (nothing is ever discarded before it is saved):
//   1. Local backup (never pushed): patch of all tracked changes + tarball of untracked files
//      → .trailbook/rescue/<project>/<stamp>/   (gitignored in the workspace)
//   2. Rebase / cherry-pick / revert in progress → abort it (backup + note keep the partial state).
//      Merge in progress → `merge --quit` (tree kept), committed as-is (conflict markers included) on the rescue branch.
//   3. Secret-looking untracked files (.env, *.pem, *.key, id_*, credentials*, …) → stashed locally, NOT pushed.
//   4. Everything else → committed on branch rescue/<stamp>-<from>, pushed, draft PR to <base>.
//      Commit impossible → git stash (noted).
//   5. Switch to <base> (forced only as a last resort — everything is backed up by then).
//   6. Local <base> has commits not on origin → saved on rescue/<stamp>-local-<base> (pushed, draft PR),
//      then <base> is reset to origin/<base>.
//   7. Note → work/<project>/<stamp>-rescue/rescue.md + line in work/index.md.
//
// Usage: node tools/checkout-base.mjs <project-name> [base-branch]   (base defaults to the card's `branch:`)
// Last lines of output: STATUS: CLEAN | RESCUED | FAILED, NOTE: <path>, FLAGS: <list>
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ws, run, cardField, isDir, readText, lines, slashes, stamp as mkStamp, today } from './_lib.mjs';

const [name, baseArg] = process.argv.slice(2);
if (!name) { console.error('usage: checkout-base.mjs <project> [base]'); process.exit(1); }
const R = `${ws}/projects/${name}`;
const base = baseArg || cardField(`${ws}/projects/ws_${name}.md`, 'branch');
const fail = (reason) => { console.log(`STATUS: FAILED\nREASON: ${reason}`); process.exit(1); };
if (!isDir(`${R}/.git`)) fail(`${R} is not a git checkout`);
if (!base) fail('no base branch (card branch: missing)');

const g = (...a) => run('git', ['-C', R, ...a]);                     // stderr shown
const gq = (...a) => run('git', ['-C', R, ...a], { quiet: true });   // stderr hidden
const ok = (r) => r.code === 0;
const text = (r) => r.out.trim();
const list = (r, sep = '\n') => r.out.split(sep).filter(Boolean);
const gp = (p) => fs.existsSync(path.resolve(R, text(g('rev-parse', '--git-path', p))));   // git-path is relative to the repo
const porcelain = () => text(g('status', '--porcelain'));
const hasOriginBase = () => ok(g('rev-parse', '-q', '--verify', `origin/${base}`));
const ahead = () => Number(text(g('rev-list', '--count', `origin/${base}..${base}`)) || 0);

if (!ok(g('fetch', '-q', 'origin', '--prune'))) console.log('warn: fetch failed (offline?) — continuing with local refs');
const dirty = porcelain();
let op = '';
if (gp('MERGE_HEAD')) op = 'merge';
if (gp('rebase-merge') || gp('rebase-apply')) op = 'rebase';
if (gp('CHERRY_PICK_HEAD')) op = 'cherry-pick';
if (gp('REVERT_HEAD')) op = 'revert';

function syncBase() {   // on a clean tree: switch + pull; handle a diverged local base. → 0 ok | 1 failed | 2 diverged
  if (!ok(gq('switch', '-q', base)) && !ok(gq('switch', '-q', '-c', base, '--track', `origin/${base}`))) return 1;
  if (hasOriginBase()) {
    if (ahead() > 0) return 2;
    if (!ok(g('pull', '-q', '--ff-only', 'origin', base))) return 1;
  }
  return 0;
}

if (!dirty && !op && syncBase() === 0) {
  console.log(`on ${base} @ ${text(g('rev-parse', '--short', 'HEAD'))} (up to date with origin)\nSTATUS: CLEAN`);
  process.exit(0);
}

// ---------- rescue ----------
const stamp = mkStamp();
const from = text(g('branch', '--show-current')) || `detached-${text(g('rev-parse', '--short', 'HEAD'))}`;
const slug = from.replace(/[/ ]/g, '-').replace(/[^A-Za-z0-9._-]/g, '');
const bkRel = `.trailbook/rescue/${name}/${stamp}`;
const bk = `${ws}/${bkRel}`;
const taskRel = `${name}/${stamp}-rescue`;
const task = `${ws}/work/${taskRel}`;
fs.mkdirSync(bk, { recursive: true });
fs.mkdirSync(task, { recursive: true });
const flags = [];
const prs = [];
const log = [];
const say = (s) => { log.push(`- ${s}`); console.log(s); };
const flagList = () => flags.join(' ');

fs.writeFileSync(`${bk}/status.txt`, `${g('status', '--porcelain=v2', '-b').out}\n${g('stash', 'list').out}`);
const patchTo = (...diffArgs) => {   // binary-safe: git writes straight into the file
  const fd = fs.openSync(`${bk}/tracked.patch`, 'w');
  const r = spawnSync('git', ['-C', R, 'diff', ...diffArgs, '--binary'], { stdio: ['ignore', fd, 'ignore'], windowsHide: true });
  fs.closeSync(fd);
  return r.status === 0;
};
if (!patchTo('HEAD')) patchTo();
const untracked = list(g('ls-files', '--others', '--exclude-standard', '-z'), '\0');
if (untracked.length) {
  // file list via -T (no command-line length limit); relative archive path (GNU tar reads `C:` as a remote host)
  fs.writeFileSync(`${bk}/untracked.list`, untracked.map((f) => `${f}\0`).join(''));
  const rel = (p) => slashes(path.relative(R, p));
  const tar = run('tar', ['-czf', rel(`${bk}/untracked.tgz`), '--null', '-T', rel(`${bk}/untracked.list`)], { cwd: R, quiet: true });
  if (ok(tar)) fs.rmSync(`${bk}/untracked.list`, { force: true });
  else {   // no usable tar → plain copies
    fs.rmSync(`${bk}/untracked.tgz`, { force: true });
    for (const f of untracked) {
      try { fs.cpSync(`${R}/${f}`, `${bk}/untracked/${f}`, { recursive: true, verbatimSymlinks: true }); } catch { /* best effort */ }
    }
  }
}
say(`local backup (not pushed): ${bkRel}`);
const conflicted = list(g('diff', '--name-only', '--diff-filter=U'));
if (conflicted.length) flags.push('conflicts');

if (op === 'rebase' || op === 'cherry-pick' || op === 'revert') {
  if (ok(g(op, '--abort'))) say(`aborted in-progress ${op} (partial state in backup)`);
  flags.push(`${op}-aborted`);
} else if (op === 'merge') {
  const mh = text(g('rev-parse', '--short', 'MERGE_HEAD'));
  if (ok(g('merge', '--quit'))) say(`merge of ${mh} into ${from} was in progress → quit (working tree kept) and committed as-is, conflict markers included, on the rescue branch`);
  flags.push('merge-in-progress');
}

function pushPr(branch, title) {
  if (!ok(gq('push', '-q', '-u', 'origin', branch))) { say(`push of ${branch} failed — branch kept locally`); flags.push('not-pushed'); return; }
  const body = `Automatic rescue by Trailbook before switching to \`${base}\`. Nothing here was reviewed — see the workspace note \`work/${taskRel}/rescue.md\`. Close without merging once resolved.`;
  const url = text(run('gh', ['pr', 'create', '--draft', '--base', base, '--head', branch, '--title', title, '--body', body], { cwd: R, quiet: true }));
  if (url) { prs.push(url); say(`draft PR: ${url}`); } else { say(`pushed ${branch} (no PR created — open one manually)`); flags.push('no-pr'); }
}

if (porcelain()) {
  // secret-looking untracked files: keep local only
  const secretRe = /(^|\/)(\.env(\..*)?|.*\.(pem|key|p12|pfx|jks)|id_(rsa|ecdsa|ed25519)(\.pub)?|credentials.*|.*secret.*|.*\.kdbx)$/i;
  const sensitive = untracked.filter((f) => secretRe.test(f));
  if (sensitive.length && ok(g('stash', 'push', '-q', '-u', '-m', `trailbook rescue ${stamp}: sensitive files (local only)`, '--', ...sensitive))) {
    say(`stashed ${sensitive.length} secret-looking file(s) locally, not pushed: ${sensitive.join(' ')}`);
    flags.push('sensitive-stashed');
  }
  const rb = `rescue/${stamp}-${slug}`;
  if (ok(g('switch', '-q', '-c', rb)) && ok(g('add', '-A'))
      && ok(g('-c', 'core.hooksPath=/dev/null', 'commit', '-q', '--no-verify', '-m', `rescue: leftover work on ${from} before switching to ${base}`))) {
    say(`committed leftovers on ${rb}`); flags.push('leftovers');
    pushPr(rb, `rescue: leftover work on ${from} (${stamp})`);
  } else {
    if (ok(g('stash', 'push', '-q', '-u', '-m', `trailbook rescue ${stamp}: leftovers from ${from}`))) say('commit failed → stashed leftovers (git stash list)');
    flags.push('stashed');
  }
}

let rc = syncBase();
if (rc === 1) {
  if (ok(g('switch', '-q', '-f', base))) { say(`forced switch to ${base} (everything backed up first)`); flags.push('forced-switch'); }
  gq('pull', '-q', '--ff-only', 'origin', base);
  rc = syncBase();
}
if (rc === 2) {
  const lb = `rescue/${stamp}-local-${base}`;
  if (ok(g('branch', lb, base))) say(`local ${base} had ${ahead()} commit(s) not on origin → saved on ${lb}`);
  flags.push('base-diverged');
  pushPr(lb, `rescue: unpushed local commits on ${base} (${stamp})`);
  if (ok(g('reset', '-q', '--hard', `origin/${base}`))) say(`reset ${base} to origin/${base}`);
}

const head = text(gq('rev-parse', '--short', 'HEAD'));
const cur = text(g('branch', '--show-current'));
let status;
if (cur === base && !porcelain() && (!hasOriginBase() || text(g('rev-parse', 'HEAD')) === text(g('rev-parse', `origin/${base}`)))) {
  status = 'RESCUED'; say(`now on ${base} @ ${head}, clean, matches origin`);
} else {
  status = 'FAILED'; say(`could not reach a clean ${base} (on '${cur}', see git status)`);
}

const note = [
  '---', `title: Rescue before checking out ${base} (${name})`, 'type: rescue', `project: ${name}`,
  `date: ${today()}`, 'status: needs-review', `from: ${from}`, `flags: [${flagList()}]`, '---',
  `**TL;DR:** couldn't switch \`${name}\` to \`${base}\` cleanly; leftovers were saved (${flagList() || 'none'}) and the repo was moved to \`${base}\`. Review and close the rescue PR(s).`,
  '', '## What happened', ...log,
  '', '## State before rescue', '```', ...(readText(`${bk}/status.txt`) ?? "").replace(/\n$/, "").split("\n").slice(0, 40), '```',
  ...(conflicted.length ? ['', '## Conflicted files', ...conflicted.map((f) => `- ${f}`)] : []),
  '', '## Recover',
  `- Rescue PRs: ${prs.join(' ') || 'none'}`,
  `- Local backup (this machine only): \`${bkRel}\` — \`git apply tracked.patch\`, \`tar -xzf untracked.tgz\``,
  `- Stashes: \`git -C projects/${name} stash list\` (look for "trailbook rescue ${stamp}")`,
];
fs.writeFileSync(`${task}/rescue.md`, `${note.join('\n')}\n`);

const indexFile = `${ws}/work/index.md`;
const index = readText(indexFile);
if (index !== null && /^## Open/m.test(index)) {
  const entry = `- ${name} · [${stamp}-rescue](${taskRel}/) — rescue before checkout of ${base} (${flagList() || 'none'}) · rescue · needs-review · doc: rescue.md · PR: ${prs.join(' ') || '—'}`;
  fs.writeFileSync(indexFile, index.replace(/^## Open.*$/gm, (m) => `${m}\n${entry}`));
}

console.log(`STATUS: ${status}\nNOTE: work/${taskRel}/rescue.md\nFLAGS: ${flagList() || 'none'}`);
process.exit(status === 'FAILED' ? 1 : 0);

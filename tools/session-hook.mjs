#!/usr/bin/env node
// Session hook for the wiki-filing reminder. Node twin of tools/session-hook.sh (same output).
// Works in Claude Code and GitHub Copilot (Copilot reads the same .claude/settings.json;
// PascalCase events get snake_case fields).
//   start → reminder that the wiki is only updated when the session is closed deliberately,
//           plus a warning listing earlier sessions that ended without being filed.
//   stop  → remember this session's transcript path (Copilot's SessionEnd payload has none).
//   end   → if this session was never filed and had real conversation (≥ 3 user prompts),
//           record it in .trailbook/unfiled-sessions.
// Usage (from settings.json): node tools/session-hook.mjs start|stop|end   (hook JSON on stdin)
// One process, no forks: the transcript is extracted in-process (tools/session-extract.mjs).
// Fail-safe by design: a hook must never break anyone's session. Any error → exit 0 silently
// (the AGENTS.md rule still makes the agent give the reminder).
import fs from 'node:fs';
import { ws, readText, lines, walk, today } from './_lib.mjs';

async function main() {
  process.chdir(ws);
  const state = '.trailbook/unfiled-sessions';
  let payload = {};
  try { payload = JSON.parse(fs.readFileSync(0, 'utf8')) ?? {}; } catch { /* no stdin / not JSON */ }
  const str = (...keys) => { for (const k of keys) if (typeof payload[k] === 'string' && payload[k]) return payload[k]; return ''; };

  const sid = str('session_id', 'sessionId');
  let tp = str('transcript_path', 'transcriptPath');
  const src = str('source') || 'startup';
  const mode = process.argv[2] ?? 'start';
  // Claude Code sets CLAUDE_PROJECT_DIR for hooks; Copilot doesn't.
  const harness = process.env.CLAUDE_PROJECT_DIR ? 'claude' : 'copilot';
  const safeId = /^[\w.-]+$/.test(sid);   // the id becomes a file name

  let sessions = null;   // raw/sessions contents, read once
  const filed = (id) => {
    sessions ??= walk('wiki/raw/sessions').map((f) => readText(f) ?? '');
    return sessions.some((t) => t.includes(`session: ${id}`));
  };

  if (mode === 'stop') {
    if (!sid || !tp || !safeId) return;
    fs.mkdirSync('.trailbook/transcripts', { recursive: true });
    fs.writeFileSync(`.trailbook/transcripts/${sid}`, `${tp}\n`);
    if (harness !== 'claude') console.log('{}');
    return;
  }

  if (mode === 'end') {
    if (!sid || filed(sid)) return;
    if (!tp && safeId) tp = (readText(`.trailbook/transcripts/${sid}`) ?? '').trim();
    const { extract } = await import('./session-extract.mjs');
    const prompts = lines(extract(tp || sid)).filter((l) => l.startsWith('**User:**')).length;
    if (prompts < 3) return;
    fs.mkdirSync('.trailbook', { recursive: true });
    if (!(readText(state) ?? '').includes(sid)) {
      fs.appendFileSync(state, `${sid} ${today()} prompts=${prompts} ${tp ? `transcript=${tp}` : ''}\n`);
    }
    return;
  }

  // start
  if (src === 'compact') return;
  let pending = lines(readText(state)).filter((l) => l.trim());
  if (pending.length) {
    pending = pending.filter((l) => !filed(l.split(/\s+/)[0]));
    fs.writeFileSync(state, pending.map((l) => `${l}\n`).join(''));
  }
  const n = pending.length;
  let msg = '📚 Trailbook: the wiki is only updated when you END this session deliberately — say "done" (or /session-close) before closing. Closing without it files nothing.';
  let ctx = 'Workspace reminder: wiki filing happens only via skill session-close when the user says the session is done. Tell the user this in one line at the top of your first reply (they may not see hook messages), and again in one line whenever a unit of work finishes.';
  if (n > 0) {
    msg += `\n⚠️ ${n} earlier session(s) ended without filing — say "file unfiled sessions" to ingest them (ids in ${state}).`;
    ctx += ` Unfiled earlier sessions are listed in ${state} ('<session-id> <date> prompts=<n> [transcript=<path>]' per line); mention them and offer to file them via session-close.`;
  }
  const j = JSON.stringify;
  if (harness === 'claude') {
    console.log(`{"systemMessage":${j(msg)},"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":${j(ctx)}}}`);
  } else {
    console.log(`{"additionalContext":${j(`${msg}\n\n${ctx}`)}}`);   // Copilot consumes only additionalContext on sessionStart
  }
}

main().catch(() => {}).finally(() => { process.exitCode = 0; });

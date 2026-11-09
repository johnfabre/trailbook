---
name: session-close
description: End-of-session wrap-up — extracts the session transcript (code-free) and has a haiku wiki-ingester file its decisions, whys, and learnings into the wiki. Run whenever the user signals the session is done ("done", "that's all", "wrap up", "end session", "closing", "/session-close").
updated: 2026-11-08
---

# Session close

Goal: the wiki always knows what happened and **why**, without storing code, at near-zero cost.

## Steps
1. **Finish open work first**: anything mid-flight (uncommitted dev work, pending gates) → tell the user in one line what's left; don't block on it.
2. **Extract** the transcript into a raw source (Claude Code):
   ```bash
   tools/session-extract.sh <session-id> -o wiki/raw/sessions/<YYYY-MM-DD>-<slug>.md && chmod a-w wiki/raw/sessions/<YYYY-MM-DD>-<slug>.md
   ```
   - `<session-id>`: Claude Code — the UUID in your scratchpad path. Copilot — omit it: the script picks the most recent transcript of this workspace (VS Code chat sessions are supported).
   - `<slug>`: 2–4 words naming the session's main topic.
   - Output keeps user messages, assistant prose, and one-line action summaries; drops code, tool output, thinking; redacts obvious secrets.
   - Harness with no readable transcript (e.g. Copilot CLI, cloud agents): write the raw file yourself — bullet list of decisions + why, facts learned, files/PRs touched. No code.
3. **Hints** (≤ 5 lines, from your own context — cheap and the ingester can't infer them): main topic, key decisions, projects + task dirs + PRs touched, anything the user stressed.
4. **Spawn** per skill `wiki-ingest` main-agent steps 3–4 with kind `session` (haiku unless the session was unusually long and technical → sonnet):
   `🤖 spawning wiki-ingester — file session "<slug>" into wiki — model haiku/low`
5. **Check** the ingester's STATUS block: pages created/updated, or `nothing durable to file`.
6. **Log** is written by the ingester.
7. **Commit + push the filing** (always — the user pre-authorized this; no need to ask). Only the filing's paths, never other uncommitted work:
   ```bash
   paths="wiki log.md $(git diff --name-only -- 'projects/ws_*.md')"   # + cards the ingester touched
   git add -- $paths
   git commit -m "wiki: file session <slug>" -- $paths        # add your harness's commit trailer if it uses one
   git pull --rebase --autostash -q && git push -q
   ```
   - Nothing changed (`NOTHING_TO_FILE`) → still commit the raw transcript + log line.
   - Pull/push fails (offline, conflict, auth) → leave the commit local, tell the user in one line; never force-push.
   - Other uncommitted workspace changes stay untouched → mention them in one line.
8. **Report** the result: `📚 session filed + pushed: <n> pages (<decisions>) → <short sha>`.

## Unfiled sessions
`.trailbook/unfiled-sessions` (written by the SessionEnd hook) lists sessions that ended without filing: `<session-id> <date> prompts=<n>`.
On "file unfiled sessions" (or when offered at session start): for each id → steps 2 + 4 (no hints available — say so in the prompt), one haiku ingester per session, in parallel; then step 7 once for all of them (`wiki: file <n> unfiled sessions`). The SessionStart hook drops entries once `wiki/raw/sessions/` contains their `session:` id.

## Skip / shortcut
- Session was only a quick lookup with no new info → skip extraction, say `nothing to file`.
- User says "close without filing" → skip.

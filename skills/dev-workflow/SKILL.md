---
name: dev-workflow
description: Mandatory entry point for any development work (code change, bug fix, feature, refactor, data-model change) in a project under projects/. Classifies the change as simple or complex, sets up the task folder, and defines the subagent handoff protocol. Use whenever the user asks to fix, build, change, or implement something in a project.
updated: 2026-11-08
---

# Dev workflow (entry point)

Main agent = orchestrator. It **does not write project code itself**. Roles run as subagents (`agents/*.md`) so their file reads and test output stay out of the main context.

## 1. Resolve project
`projects/index.md` → card `ws_<name>.md`. Note: `branch:` (default/base), `Commands`, `Instructions` pointer, `ui:` flag, `Models:` override. Not onboarded → skill `onboard-project` first.
**Project skill**: card `skill: ws-project-<name>` → load it **now, before classifying** (Skill tool; not listed yet → read `projects/ws_<name>.skill.md`). It maps the repo's own AI files (flows, role files, rules) onto this workflow: **repo files win where they conflict, this workflow applies everywhere else.** Its § Conflicts overrides the matching steps below and in simple-/complex-change; its § Spawning roles extends §5.

## 2. Classify

| simple-change (surgical) | complex-change |
|---|---|
| bug fix / small tweak, 1 lib/package, ~≤ 5 files | new feature or user-visible behavior |
| no data-model, schema, API-contract change | touches data model, migrations, public API |
| intent clear from request | spans multiple libs/packages/services |
| | requirements need clarifying |

**trivial** (typo, copy text, config value, local rename; ≤ 2 files, ≤ 20 lines, no logic) → skill `trivial-change`:
main agent edits inline, `tools/trivial-gate.sh` + one haiku review, auto-promotes to simple-change on any doubt.
Unsure between classes → the bigger one. State choice to user in one line (`→ trivial-change: <why>`); user may override.
Then load skill `trivial-change`, `simple-change`, or `complex-change`.

## 3. Task folder (shared by both flows)
```
work/<project>/<YYYY-MM-DD>-<slug>/
  brief.md       main agent: request, scope, acceptance criteria, card commands
  spec.md        BA (complex only) — precise doc
  review.md      visual digest of spec/brief for the user (skill present-visually)
  mockups/       annotated HTML mockups (UI only)
  ux.md          UX expert (if UI); ux-review-<n>.md
  test-plan.md   QA prep (complex only)
  dev-<n>.md     developer notes per round
  review-<n>.md  code reviewer, one per round
  ba-review-<n>.md  BA review of test plan
  qa-<n>.md      QA, one per round
  status.md      main agent: one line per stage transition
```
Tracked in workspace git — specs and verdicts are project history.
On creation add a line to `work/index.md`; update its status at every gate (approved, pr-open, done…).

## 4. Git (in the project repo)
**Every dev task starts from a fresh default branch** (`<base>` = card `branch:`; the user's choice wins over the remote's HEAD). Checkout is **always** followed by a pull — the script does both:
```bash
tools/checkout-base.sh <name>                    # fetch → switch <base> → pull --ff-only; rescues anything in the way
git -C projects/<name> switch -c <fix|feat|chore>/<slug>     # exists already → ask: reuse or new name
```
Read only the script's last 3 lines (`STATUS`, `NOTE`, `FLAGS`):
- `CLEAN` → continue.
- `RESCUED` → leftovers / conflicts / local commits were saved before switching (backup in `.trailbook/rescue/`, rescue branch + **draft PR**, secret-looking files stashed locally only, note in `work/<name>/<stamp>-rescue/rescue.md`, line in `work/index.md` as `needs-review`). Then:
  1. Tell the user, before continuing: what was in the way, where it went (PR links, stash, backup), from the note's "What happened".
  2. **Recommend a separate session** to investigate when FLAGS contain any of `conflicts`, `merge-in-progress`, `rebase-aborted`, `cherry-pick-aborted`, `revert-aborted`, `base-diverged`, `stashed`, `sensitive-stashed`, `not-pushed` — or the leftovers look like unfinished real work (many files, or match an open task in `work/index.md`). Otherwise: "low risk — review and close the rescue PR when convenient".
  3. Continue the current task on its new branch from the fresh `<base>` (don't mix rescue work into it).
- `FAILED` → stop; show the note; ask the user. Nothing was discarded.
- **Never commit or push to `<base>`.** All work lives on the task branch; it reaches `<base>` only through a PR.
- Developer and QA edit the working tree. **Only the main agent commits** (on the task branch).
- Never discard, reset, or force anything by hand — `checkout-base.sh` saves first (local commits on `<base>` go to a `rescue/…-local-<base>` branch before `<base>` is reset to origin).

## 5. Handoff protocol
**Announce first** (mandatory, user-visible, in the same message as the spawn call — see AGENTS.md hard rules):
```
🤖 spawning developer — implement brief (fix invoice rounding) — model sonnet/medium
🔁 resuming developer r2 — address review-1.md (2 blockers) — model sonnet/medium
⬆️ escalating code-reviewer sonnet → opus — gate failed twice on concurrency logic
```
Parallel spawns → one line per agent. The model shown must be the one actually passed in the call.

**Spawn** each role with a short prompt: role file is auto-loaded; pass only paths —
`task dir`, `repo path`, `card path`, round number, and what to do. Never paste file contents into the prompt.
Without subagent support (non-Claude agents): play the role inline by reading `agents/<role>.md`, still writing artifacts to the task dir.
Project skill defines repo role files → add its "Primary role file" preamble to the prompt; the role's SUMMARY must name the role file it read (main agent checks it).

**Every role ends its reply with exactly:**
```
STATUS: <DONE | APPROVED | CHANGES_REQUESTED | PASS | FAIL | BLOCKED>
ARTIFACT: <path in task dir>
SUMMARY: <≤ 5 lines>
```
Main agent reads only this block. Open the artifact only when routing needs it (e.g. to pass review findings to the developer — pass the *path*, not text).

**Re-rounds reuse the agent** (Claude Code): for round n+1 of the same role, continue the previous agent (SendMessage to its id/name) instead of spawning fresh — it already holds the code context. Spawn fresh only if escalating model (§5a) or the agent is gone.
**Copilot**: subagents are stateless (no follow-ups) → every round is a fresh spawn; the task-dir artifacts (`dev-<n>.md`, `review-<n>.md`, …) carry the state, so pass the latest paths.

**Spawn mechanics per harness** (same roles, same files — `agents/` is exposed as `.claude/agents`, which both read):
| | Claude Code | GitHub Copilot (VS Code / CLI) |
|---|---|---|
| tool | `Agent` with `subagent_type: <role>` | `runSubagent` (Local) / `task` (Copilot harness), naming the agent `<role>` |
| model | `model` param | explicit model param of `runSubagent`; else the agent file's `model:` |
| parallel | several calls in one message | if parallel isn't available, run them one after another — order doesn't change results |

## 5a. Model routing (orchestrator picks per spawn)
Pass `model` + `effort` on every spawn. Cheapest tier that can do the job; escalate on failure, never start high "to be safe".
Relative cost (in/out per MTok): haiku $0.10/$0.50 · sonnet $2/$10 · opus $4/$20 · fable $10/$50.
Tiers are abstract: in Copilot pass the picker identifier of the same-tier model (Claude Haiku / Sonnet / Opus …); tier not offered → next tier up. Copilot bills premium requests per model multiplier — cheapest-first still holds.

| Role · task | trivial (typo, rename, config, copy) | simple-change | complex-change |
|---|---|---|---|
| business-analyst · spec | — | — | opus · high |
| business-analyst · test-plan review | — | — | sonnet · medium |
| ux-expert · wireframe / review | — | sonnet · medium | sonnet · high |
| developer | main agent inline (no spawn) | sonnet · medium | opus · high (sonnet · high if spec is very concrete) |
| code-reviewer | haiku · low | sonnet · medium | opus · high |
| qa-tester · prep (test plan) | — | — | sonnet · medium |
| qa-tester · execute: write + run tests | — (main runs card's fast check) | sonnet · medium | sonnet · high |
| qa-tester · re-run only (tests exist, verify fix) | haiku · low | haiku · low | haiku · medium |

Rules:
- **Bump to opus regardless of class**: security/auth, payments, data migrations, concurrency, public API contracts.
- **Reviewer ≥ developer tier** on complex work (a cheaper reviewer misses what a stronger dev got wrong).
- **Escalate** one tier (haiku → sonnet → opus) when the same gate fails twice at a tier, or on `BLOCKED` due to difficulty. Escalation = fresh spawn with the latest artifacts.
- **fable**: never by default. Only after opus fails a gate twice, or user asks. Confirm with user first (5× sonnet cost).
- **Project override**: card line `**Models:** dev=opus (gnarly legacy code)` beats this table for that project.
- Record choice per transition in `status.md`: `HH:MM developer r1 [sonnet/medium] DONE`.
- Retro: a tier that keeps failing (or keeps over-delivering) on a project → write/adjust the card's `Models:` line.

## 6. Loop limits
Each gate (review, QA, spec iteration) max **3 rounds**. Round 4 → stop, summarize blockers to user, ask how to proceed. `BLOCKED` from any role → surface to user immediately.

## 7. Optional add-ons (both flows)
- UI touched (card `ui: true` or diff touches views/styles/components) → `ux-expert` (wireframe before dev, review after) — complex flow; in simple flow only if the change is visual.
- Any UI → every role applies skill `a11y` (WCAG 2.2 AA). Roles read `skills/a11y/SKILL.md` themselves.

## 8. Finish (main agent)
1. Read final `review-<n>.md` + `qa-<n>.md` verdict blocks; `git -C <repo> diff --stat`.
2. Spot-check diff against `brief.md` acceptance criteria.
3. Commit on the task branch (conventional message), then **always** a PR — never push `<base>`:
   ```bash
   git -C $R branch --show-current          # must be the task branch, not <base> → else STOP
   git -C $R push -u origin <task-branch>
   gh pr create -R <owner/repo> --base <base> --head <task-branch> --title "…" --body-file <task dir>/pr.md
   ```
   PR body: brief summary + links to spec/verdicts. Non-GitHub remote → that host's CLI (`glab mr create …`) or give the user the compare URL.
4. **Merge only on explicit user go-ahead.**
5. Retro (cheap, mandatory):
   - Learned commands / gotchas → update card.
   - Domain knowledge + lasting decisions (why X over Y) → not written inline; captured at `session-close` (or spawn `wiki-ingester` now on the task dir if the session continues long).
   - `work/index.md` line → `done` (or `pr-open`), move to `## Done` when merged.
   - Repeatable discovery → skill-create (announce per AGENTS.md).
   - Log `## [date] dev | <project>: <slug> (simple|complex) → PR #n`.

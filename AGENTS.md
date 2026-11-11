# AGENTS.md — Trailbook AI Workspace

This folder is a persistent workspace for AI agents. It holds three things:
**wiki/** (what we know), **projects/** (what we work on), **skills/** (how we do repeat work).
Core goal: **cheap context**. Answer from small index/card files; never re-derive what is already written down.
Wiki scope: **general personal knowledge** — any domain (tech, work, health, finance, books, hobbies, people…), not just code.

`CLAUDE.md` is a symlink to this file. `.claude/skills` → `skills/`, `.claude/agents` → `agents/`.
Human viewer: the workspace root is an **Obsidian vault** (`.obsidian/` config tracked; repo checkouts hidden from it).

## Layout

```
AGENTS.md            this file: rules + router (README.md = human overview)
log.md               append-only log of every workspace operation
wiki/index.md        catalog of all wiki pages (1 line each)
wiki/raw/            immutable source documents (never edit); raw/sessions/ = extracted session transcripts
wiki/{sources,decisions,entities,concepts,notes}/   LLM-owned pages (decisions = the whys)
projects/index.md    project registry (1 line each)
projects/ws_<name>.md   project card (≤ 40 lines)
projects/ws_<name>.skill.md  project skill: maps repo's own AI files onto Trailbook (repo wins on conflict); exposed as gitignored link skills/ws-project-<name>/
projects/<name>/     git checkout — always here, never elsewhere (gitignored, its own repo)
skills/index.md      skill catalog (1 line each)
skills/<name>/SKILL.md  skill body
agents/<role>.md     subagents: dev-workflow roles + wiki-ingester
work/index.md        registry of every task/plan (1 line each, with status)
work/<project>/<date>-<slug>/   task artifacts: brief/spec/plan, review.md digest, mockups/, reviews, QA
tools/wiki-lint.sh   mechanical lint (links, orphans, indexes); exit 0 = clean
tools/projects-restore.sh   re-clone every registered project missing locally (new machine) + re-link project skills
tools/project-skill-link.sh  link projects/ws_*.skill.md → skills/ws-project-*/SKILL.md
tools/session-extract.sh    session transcript → code-free markdown for ingest
tools/trivial-gate.sh       size/risk gate for trivial-change (OK | PROMOTE)
tools/checkout-base.sh      default branch + pull for a project; rescues leftovers/conflicts to a PR first
tools/session-hook.sh       SessionStart/End hook: filing reminder + unfiled-session tracking (.claude/settings.json)
tools/obsidian-open.sh      open a vault file in Obsidian (obsidian:// URI; Linux/macOS/Windows)
```

## Harnesses (Claude Code and GitHub Copilot, like-for-like)
Both load this file, `.claude/skills/` (skills) and `.claude/agents/` (subagents, Claude format — Copilot maps tools and `haiku|sonnet|opus`), and run hooks from `.claude/settings.json`.
Differences are handled inside the skills: Copilot subagents are stateless (fresh spawn each round), spawn via `runSubagent`/`task`, and hook banners may not be shown — so the agent states the reminders itself.

## Read order (cheapest first) — mandatory

| Tier | What | When |
|---|---|---|
| T0 | this file | always loaded |
| T1 | `wiki/index.md`, `projects/index.md`, `skills/index.md` | first stop for any lookup |
| T2 | head of a card / page (`head -20`: frontmatter + TL;DR) | usually enough |
| T3 | full wiki page or full skill | when T2 is not enough |
| T4 | project repo files, `wiki/raw/` sources | only when doing real work on them |

- Never go to tier N+1 if tier N answers the question.
- Never read repo files to learn *what a project is* — the card answers that. If it doesn't, fix the card.
- Search beyond indexes: `grep -ril '<term>' wiki/ --exclude-dir=raw` then read heads of matches.
- Recent activity: `grep '^## \[' log.md | tail -10`.

## Router

| Situation | Action |
|---|---|
| **Any dev work in a project** — fix, feature, refactor, change code | **skill `dev-workflow` — mandatory, before touching code** |
| User names a project ("in billing…", "the api repo") | match name/aliases in `projects/index.md` → read `ws_<name>.md` → card `skill:` set → load that project skill → only then touch repo |
| "check out / clone / onboard X", or project not in registry | skill `onboard-project` |
| Card looks stale or wrong | skill `onboard-project` (refresh mode) |
| "use `<branch>` as default for X" | skill `onboard-project` § Change default branch |
| "add / read / ingest this source" | skill `wiki-ingest` (always a `wiki-ingester` subagent, haiku first) |
| **User signals session is done** ("done", "that's all", "wrap up", "end session") | **skill `session-close` — mandatory** (files the session's whys into the wiki) |
| "file unfiled sessions" | skill `session-close` § Unfiled sessions |
| Knowledge or "why did we…" question | skill `wiki-query` (index → decisions/pages → answer with citations) |
| "lint / health-check the wiki" | skill `wiki-lint` |
| Presenting a plan, spec, design, review, comparison, or anything multi-part | skill `present-visually` (chunks, mermaid, tables, annotated HTML mockups) |
| User is in a terminal ("I'm in CLI", "can't see mermaid") | skill `present-cli` — visuals to a vault `.md`, opened in Obsidian; sticky for the session |
| "review / show the plan for <feature> in <project>" | `work/index.md` → task dir → skill `present-visually` §7 |
| Task looks repeat-shaped | check `skills/index.md` before figuring it out from scratch |
| Just finished something worth reusing | skill `skill-create` |

## When to create a skill (agents do this proactively)

Create or update a skill when **all** hold:
1. Procedure will recur (done ≥ 2×, or obviously will be).
2. It took real discovery: trial and error, multi-step order, non-obvious flags or gotchas.
3. It worked and is stable enough to write down.

Not for one-offs, or things a project's own docs already cover (link those from the card instead).
Write skills only **after** the task succeeds, from what actually worked. Prefer updating an existing skill over making a near-duplicate.
Auto-create, but **never silently**: every new or updated skill must be announced to the user in the same reply:
`saved skill <name> (new|updated): <what it does> → skills/<name>/SKILL.md`. User may veto → delete/revert it.

## Conventions

- **Filenames**: kebab-case. Wiki pages carry a type prefix: `src-`, `decision-`, `entity-`, `concept-`, `note-`. Project cards: `ws_<name>.md`.
- **Links**: Obsidian wikilinks `[[page-slug]]` (no `.md`). Slugs are unique across the wiki.
- **Dates**: ISO `YYYY-MM-DD`.
- **Wiki page head** (keeps T2 reads useful):
  ```
  ---
  title: ...
  type: source | decision | entity | concept | note
  tags: [..]
  sources: [src-..]
  updated: YYYY-MM-DD
  ---
  **TL;DR:** 1–3 lines.
  ```
- **Tags**: first tag = domain (`tech`, `work`, `health`, `finance`, `learning`, `people`, `home`, …; add new ones freely), then specifics.
- **Index line**: `- [[slug]] — one-line summary #domain` (≤ ~120 chars). Every index is grouped by type/status.
- **Personal/sensitive info**: fine to store (private repo), but never secrets — passwords, tokens, keys go in a password manager; the wiki notes only *where* they live.
- **Plans & specs** live in `work/` (task artifacts), not the wiki; the wiki gets only the lasting decisions, linked back.
- **Contradictions**: never silently overwrite. Note both claims with sources under a `## Conflicts` heading.

## Log format

Append to `log.md`, newest at bottom, one heading per operation:
```
## [YYYY-MM-DD] <op> | <subject>
- 1–3 bullets: what changed (files touched)
```
`<op>` ∈ `ingest, query, lint, onboard, refresh, skill, dev, setup`.

## Hard rules

- Never modify `wiki/raw/`. It is the source of truth.
- **Ingest always runs in a `wiki-ingester` subagent** — haiku by default; sonnet/opus only when the main agent judges it needed or the ingester returns `ESCALATE`. Main agent never writes ingest pages itself. No code in the wiki — decisions, whys, facts, pointers.
- Never write into a project repo (`projects/<name>/`) unless the user asks for work in it.
- Dev work always goes through `dev-workflow`: main agent orchestrates subagents, never codes directly (sole exception: `trivial-change`, gated + reviewed), only it commits; merge only on user go-ahead.
- **Project git**: every dev task starts with `tools/checkout-base.sh <project>` — checkout of the default branch (card `branch:`, set at onboarding, user can change it anytime) **always followed by a pull**; anything in the way (leftover files, conflicts, local commits) is saved to a rescue branch + draft PR + note first, never lost — then a task branch. **Never commit or push to the default branch — always a PR.**
- **Remind about filing**: the wiki updates only when the user ends the session deliberately. Say so once in your first reply of a session, and in one line whenever a unit of work finishes (task done, PR opened, plan approved): `📚 say "done" when you're finished so I file this session into the wiki`. A SessionStart hook (`tools/session-hook.sh`) also shows it, plus any earlier unfiled sessions.
- **Announce every subagent spawn** (any task, not just dev work) to the user *before* the call, one line:
  `🤖 spawning <role> — <what it will do> — model <model>/<effort>` (re-rounds: `🔁 resuming <role> r<n> — …`; escalation: `⬆️ escalating <role> <old> → <new> — <why>`).
- Any create / rename / delete of a page, card, or skill → update its index in the same step.
- **Tools need only git + bash**: scripts in `tools/` and commands in skills may use what ships with Git for Windows, macOS and Linux (coreutils, grep, sed, awk, perl core) — never python, jq, node or anything that must be installed.
- Keep this file under ~150 lines. Move long procedures into skills.
- Workspace is a git repo. Tracked: everything except `projects/*/` checkouts. Projects stay registered via cards (remote + branch), so `tools/projects-restore.sh` rebuilds them.
- Commit the workspace repo only when the user asks — **except session filing**: `session-close` always commits and pushes its own wiki/log changes (only those paths).

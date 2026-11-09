# Skills index

One line per skill. Read this before figuring out a repeat-shaped task from scratch.
Template for new skills: `_template.md`. How to add one: [skill-create](skill-create/SKILL.md).

## Workspace
- [onboard-project](onboard-project/SKILL.md) — clone/register a repo, write its ws_ card + registry line; refresh stale cards
- [wiki-ingest](wiki-ingest/SKILL.md) — add a source via wiki-ingester subagent (haiku → sonnet → opus on ESCALATE)
- [session-close](session-close/SKILL.md) — on "done": extract session transcript, file decisions/whys into wiki (haiku)
- [wiki-query](wiki-query/SKILL.md) — answer from wiki via tiered reads, cite, file good answers to notes/
- [wiki-lint](wiki-lint/SKILL.md) — broken links, orphans, unindexed pages, stale/conflicting content
- [skill-create](skill-create/SKILL.md) — turn a procedure that just worked into a skill

## Dev workflow (any code change in a project starts at dev-workflow)
- [dev-workflow](dev-workflow/SKILL.md) — entry: classify simple/complex, task dir, subagent handoff protocol, finish + PR
- [trivial-change](trivial-change/SKILL.md) — typo/copy/config: main edits inline → trivial-gate.sh → haiku review; auto-promotes to simple
- [simple-change](simple-change/SKILL.md) — surgical fix: developer ⇄ reviewer → QA → commit/PR
- [complex-change](complex-change/SKILL.md) — feature/data-model: BA spec → user gate → dev ∥ QA prep → review → QA → PR
- [a11y](a11y/SKILL.md) — WCAG 2.2 AA checklist + tooling; used by all roles on UI work

## General
- [present-visually](present-visually/SKILL.md) — show info chunk by chunk with mermaid, tables, annotated HTML mockups; review stored plans across sessions
- [present-cli](present-cli/SKILL.md) — "I'm in CLI": same as present-visually, but visuals go to a vault .md opened in Obsidian
<!-- agent-created cross-project skills go here -->

## Project-specific
<!-- <project>-<verb>-<noun> skills go here -->
<!-- ws-project-<name> skills are NOT listed here: tracked as projects/ws_<name>.skill.md, routed via the card's `skill:` field -->

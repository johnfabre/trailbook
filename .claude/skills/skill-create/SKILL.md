---
name: skill-create
description: Turn a procedure that just worked into a reusable workspace skill (.claude/skills/<name>/SKILL.md + index line), or update an existing one. Use after finishing a repeatable, non-obvious task — the agent should do this proactively per AGENTS.md criteria.
updated: 2026-11-08
---

# Create / update a skill

## Gate (all must hold — see AGENTS.md)
Recurs · took real discovery · worked and stable. Otherwise stop.

## Steps

1. **Check for existing**: `grep -ril '<keyword>' .claude/skills/`. Close match → update it instead (add steps/pitfalls, bump `updated:`).
2. **Name**: kebab-case verb-noun, e.g. `deploy-billing-api`, `rotate-db-creds`. Project-specific → prefix with project name.
3. **Copy** `.claude/skills/_template.md` → `.claude/skills/<name>/SKILL.md`.
4. **Fill from what actually worked** this session — exact commands, order, flags, file paths. Strip dead ends, but keep the gotchas they revealed under Pitfalls.
5. **Description** (frontmatter) is the trigger: say *what it does* and *when to use it* in 1–2 sentences, with words a user would actually say. Claude Code auto-loads skills by this text.
6. Keep body < ~100 lines. Long reference material → `.claude/skills/<name>/refs/*.md`; scripts → `.claude/skills/<name>/scripts/` (make executable, call from steps).
7. **Index**: add line to `.claude/skills/index.md` under right group:
   `- [<name>](<name>/SKILL.md) — <when to use>`
8. Project-specific skill → add name to card's `Skills:` line.
9. **Log**: `## [date] skill | <name> (new|updated)`.
10. **Tell user** (mandatory, same reply, also for updates): `saved skill <name> (new|updated): <what it does> → .claude/skills/<name>/SKILL.md`. If they veto, delete/revert and log it.

## Pitfalls
- Don't write skills speculatively from a plan — only from a run that succeeded.
- No secrets in skills; reference where they live (e.g. "token in 1Password: X").

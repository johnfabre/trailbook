---
name: onboard-project
description: Check out (clone) a git repository into projects/ and write its cheap project card (projects/ws_<name>.md) and registry line. Also used to refresh a stale card. Use when the user asks to clone/check out/onboard a project, or mentions a project not in projects/index.md.
updated: 2026-11-08
---

# Onboard project

Goal: capture what an agent needs to know about a repo in a ≤ 40-line card, **without** reading big files.

## Inputs
- Repo URL. Optional: name, aliases.
- Name defaults to repo dir name, kebab-case.
- All projects live in `projects/<name>/` — no repos registered from elsewhere.

## Steps

1. **Get code**
   - URL → `git clone <url> projects/<name>`
   - User points at a local repo elsewhere → clone it into `projects/` using its `origin` URL (`git -C <path> remote get-url origin`); if it has no remote, ask the user before moving anything. Never register an outside path.
   - Already in registry but folder missing → `tools/projects-restore.sh <name>`.
   - Already in registry and present → switch to *Refresh* below.
   - `remote:` must be a real cloneable URL — it is what keeps the project restorable after a fresh clone of the workspace.

2. **Cheap probe** — budget ≈ 8 small reads, all truncated. Run from repo root:
   ```bash
   git remote get-url origin; git rev-parse --short HEAD
   { git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || git remote show origin | sed -n 's/.*HEAD branch: //p'; } | sed 's#^origin/##'   # remote default branch
   git log -5 --oneline
   git ls-files | awk -F/ 'NF>1{print $1"/"} NF==1{print}' | sort | uniq -c | sort -rn | head -30   # top-level shape
   head -60 README* 2>/dev/null
   ls AGENTS.md CLAUDE.md CONTRIBUTING.md .github/copilot-instructions.md docs/ 2>/dev/null
   ```
   Then `head -40` of the **one** main manifest present: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, `build.gradle*`, `composer.json`, `Gemfile`, `*.csproj`.
   Commands: look at `scripts` (package.json), `Makefile` targets (`grep -E '^[a-zA-Z_-]+:' Makefile | head -20`), `justfile`, CI workflow `run:` lines.
   Do **not** read source files, lockfiles, or whole docs.

3. **Write card** `projects/ws_<name>.md` from template below. Unknown → leave `?`, don't guess.
   `Instructions:` = path to repo's own AGENTS.md/CLAUDE.md/CONTRIBUTING.md (pointer only), else `none`.

3b. **Project AI files** — if the probe found any of: `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.github/{agents,prompts,instructions}/`, `.claude/{agents,skills,commands}/`, `.claude/settings.json`, `.cursor/rules/`:
   ```bash
   ls -d AGENTS.md CLAUDE.md .github/copilot-instructions.md .github/{agents,prompts,instructions} .claude/{agents,skills,commands,settings.json} .cursor/rules 2>/dev/null
   for f in .claude/agents/*.md .claude/skills/*/SKILL.md .github/agents/*.md; do [ -f "$f" ] && { echo "== $f"; sed -n '2,4p' "$f"; }; done   # names + descriptions
   ```
   Then write `projects/ws_<name>.skill.md` from `project-skill-template.md` (this dir):
   - **File map**: every repo AI file → when it's used → its Trailbook counterpart.
   - **Conflicts**: read the full bodies only of repo files that overlap a Trailbook workflow (dev flows, role agents) and compare with Trailbook's; list each real conflict (gates, loop limits, artifact paths, handoff, review/test duties). Repo wins each one. Additive repo rules need no row.
   - **Settings**: repo `permissions.deny` git-push rules → mirror into root `.claude/settings.json` deny list (plus `git -C * push …` variants). Never copy `allow`, `defaultMode`, or hooks.
   - Card: `skill: ws-project-<name>`; `Skills:` line points to it.
   - `bash tools/project-skill-link.sh <name>` → exposes it as `skills/ws-project-<name>/SKILL.md` (gitignored symlink; restore re-creates it). Not listed in `skills/index.md` — the card's `skill:` field routes to it.
   - Announce: `saved skill ws-project-<name> (new): … → projects/ws_<name>.skill.md`. Skill list picks it up next session; until then `dev-workflow` reads the file directly.

4. **Registry line** in `projects/index.md` under right status heading:
   `- [ws_<name>](ws_<name>.md) — <one-liner> · aliases: a, b · <path>`

5. **Log**: `## [date] onboard | <name>` + files touched.

6. **Confirm with user** in ≤ 3 lines: show the one-liner, aliases, and **default branch** (base for all dev branches and PRs); ask to correct. Purpose is what agents guess worst.

7. Domain knowledge discovered later (architecture, business rules) → wiki pages, linked from card `Wiki:` line. Card stays small.

## Card template

```markdown
---
name: <name>
aliases: []
path: projects/<name>
remote: <url>
branch: <default branch>   # base for every dev branch + PR target; user can change anytime
stack: []
ui: false               # true → dev-workflow pulls in ux-expert + a11y
skill: none             # ws-project-<name> when the repo has its own AI files (step 3b)
status: active          # active | paused | archived
onboarded: YYYY-MM-DD
onboarded_commit: <short sha>
---
**What:** 1–3 lines: what it is, who uses it, why it exists.
**Instructions:** <path to repo's AGENTS.md / CONTRIBUTING.md | none>
**Entry points:** <3–6 key paths>
**Commands:** setup `…` · test `…` · run `…` · lint `…`
**Wiki:** [[…]]
**Skills:** <project-specific skills>
**Models:** <optional overrides of dev-workflow §5a, e.g. dev=opus (why)>
**Gotchas:**
- …
```

## Change default branch
User says "use `develop` as default for X" (any time): verify it exists (`git -C <path> ls-remote --heads origin <branch>`), update the card's `branch:`, log `refresh | <name>: default branch → <branch>`. Restore + dev-workflow read it from the card.

## Refresh mode
Trigger: card info proved wrong, or many commits since onboarding:
```bash
git -C <path> fetch -q && git -C <path> rev-list --count <onboarded_commit>..origin/<branch>
```
If > ~50 or structure changed: rerun step 2 only for changed areas, update card fields, bump `onboarded` + `onboarded_commit`, log `refresh`.
Project skill: run its § Refresh diff; AI files changed (or new ones appeared) → redo step 3b, bump its `source_commit`.

## Pitfalls
- Monorepos: list packages under Entry points; don't probe each one.
- Huge README: `head -60` only. Card links to it if needed.
- Private remotes failing to clone → ask user for auth; don't retry blindly.

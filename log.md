# Workspace log

Append-only. Recent: `grep '^## \[' log.md | tail -10`

## [2026-11-09] setup | Trailbook starting point
- bare workspace: AGENTS.md, skills/, agents/, tools/, .obsidian/; no projects, empty wiki, empty work index

## [2026-11-11] setup | tools run on stock Git Bash (no python, no jq)
- `tools/session-extract.sh` ported from python3 to module-free perl (same output); `tools/session-hook.sh` drops jq for bash + grep/sed
- new `tools/obsidian-open.sh` replaces the python URL-encoding in skill `present-cli`; `date -I` → `date +%Y-%m-%d`
- README requirements + AGENTS.md hard rule: tools need only git + bash

## [2026-11-12] setup | every tool gets a Node twin (`tools/*.mjs`) for Windows speed
- 8 new `tools/<name>.mjs` + shared `tools/_lib.mjs` (Node ≥ 18 built-ins, no npm): one process per run instead of dozens of forks; `.sh` kept as the no-node fallback, output verified identical
- hooks (`.claude/settings.json`), skills, README and AGENTS.md now call `node tools/<name>.mjs`; hard rule changed from "git + bash only" to "node primary, bash fallback, keep twins in sync"
- `wiki-lint` (both twins) flags a tool missing its twin; "no frontmatter" section now sorted

## [2026-11-26] setup | repo-review add-on drafted as a gist (not installed here)
- work/_workspace/2026-11-26-repo-review-gist/trailbook-repo-review.md: 13 files (skill + rubric + templates, 6 audit-* agents, repo-inventory + evidence-check twins)
- tools tested twin-equal on 3 repos; install + self-test verified in a throwaway clone

## [2026-11-26] setup | repo-review gist → .addons/ (inert add-ons folder)
- .addons/repo-review.md (moved from work/_workspace/…; install source = local file or a gist URL), .addons/index.md
- .ignore hides .addons/ from ripgrep searches; AGENTS.md: layout line, router row, hard rule (inert unless asked); README layout; work/index.md entry removed

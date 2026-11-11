# Workspace log

Append-only. Recent: `grep '^## \[' log.md | tail -10`

## [2026-11-09] setup | Trailbook starting point
- bare workspace: AGENTS.md, skills/, agents/, tools/, .obsidian/; no projects, empty wiki, empty work index

## [2026-11-11] setup | tools run on stock Git Bash (no python, no jq)
- `tools/session-extract.sh` ported from python3 to module-free perl (same output); `tools/session-hook.sh` drops jq for bash + grep/sed
- new `tools/obsidian-open.sh` replaces the python URL-encoding in skill `present-cli`; `date -I` → `date +%Y-%m-%d`
- README requirements + AGENTS.md hard rule: tools need only git + bash

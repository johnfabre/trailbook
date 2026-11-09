#!/usr/bin/env bash
# Re-clone registered projects whose checkout is missing (e.g. after cloning the workspace on a new machine).
# Reads `remote:` and `branch:` from each projects/ws_<name>.md card.
# Usage: tools/projects-restore.sh [name ...]    (no args = all cards; status: archived is skipped)
# Then re-links every project skill (tools/project-skill-link.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

field() { sed -n '/^---$/,/^---$/p' "$1" | sed -n "s/^$2:[[:space:]]*//p" | sed 's/[[:space:]]*#.*$//' | head -1; }

if [ $# -gt 0 ]; then cards=(); for n in "$@"; do cards+=("projects/ws_$n.md"); done
else shopt -s nullglob; cards=(); for c in projects/ws_*.md; do case $c in *.skill.md) ;; *) cards+=("$c");; esac; done; fi

for card in "${cards[@]}"; do
  [ -f "$card" ] || { echo "no card: $card" >&2; continue; }
  name=$(field "$card" name); remote=$(field "$card" remote)
  branch=$(field "$card" branch); status=$(field "$card" status)
  dir="projects/$name"
  if [ -d "$dir/.git" ]; then echo "ok       $name"; continue; fi
  if [ "$status" = archived ] && [ $# -eq 0 ]; then echo "skip     $name (archived)"; continue; fi
  if [ -z "$remote" ] || [ "$remote" = "?" ]; then echo "NO REMOTE $name — fix card" >&2; continue; fi
  echo "clone    $name ← $remote${branch:+ ($branch)}"
  git clone -q ${branch:+--branch "$branch"} "$remote" "$dir" || echo "FAILED   $name" >&2
done

# project skills (tracked projects/ws_*.skill.md → ignored skills/ws-project-*/SKILL.md)
bash tools/project-skill-link.sh

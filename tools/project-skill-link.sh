#!/usr/bin/env bash
# Expose tracked project skills to the harness.
# Source (tracked):  projects/ws_<name>.skill.md
# Loaded (ignored):  .claude/skills/ws-project-<name>/SKILL.md  → symlink to the source; a copy where symlinks are
#                    unavailable (Windows / Git Bash) — rerun after editing the source (tools/wiki-lint.sh flags stale copies)
# Usage: tools/project-skill-link.sh [name ...]   (no args = every projects/ws_*.skill.md)
# Idempotent; called by onboard-project and tools/projects-restore.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then srcs=(); for n in "$@"; do srcs+=("projects/ws_$n.skill.md"); done
else shopt -s nullglob; srcs=(projects/ws_*.skill.md); fi

for src in "${srcs[@]}"; do
  [ -f "$src" ] || { echo "no source: $src" >&2; continue; }
  n=$(basename "$src" .skill.md); n=${n#ws_}
  dir=".claude/skills/ws-project-$n"; dst="$dir/SKILL.md"; rel="../../../$src"
  mkdir -p "$dir"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$rel" ]; then echo "ok       ws-project-$n"; continue; fi
  if [ ! -L "$dst" ] && cmp -s "$src" "$dst"; then echo "ok       ws-project-$n (copy)"; continue; fi
  rm -f "$dst"
  # Git Bash's `ln -s` silently makes a copy, so check that a real link came out
  if ln -s "$rel" "$dst" 2>/dev/null && [ -L "$dst" ] && [ -f "$dst" ]; then echo "linked   ws-project-$n"
  else rm -f "$dst"; cp "$src" "$dst"; echo "copied   ws-project-$n (symlink unsupported — rerun after editing source)"; fi
done

#!/usr/bin/env bash
# Mechanical workspace lint. Portable: bash + grep/find/sort/comm only.
# Usage: tools/wiki-lint.sh   (run from anywhere)
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# page slugs (wiki pages, excluding raw/ and index)
find wiki -path wiki/raw -prune -o -name '*.md' ! -name index.md -print \
  | xargs -r -n1 basename | sed 's/\.md$//' | sort -u > "$tmp/slugs"

# link targets in wiki + project cards (skills hold placeholder examples, skip)
# inline `code` spans are stripped so documented placeholders don't count as links
links() { find "$@" -name '*.md' -exec cat {} + 2>/dev/null | sed 's/`[^`]*`//g' \
  | { grep -oE '\[\[[^]|#]+' || true; } | sed 's/^\[\[//' | sort -u; }
links wiki/sources wiki/decisions wiki/entities wiki/concepts wiki/notes wiki/index.md projects/*.md > "$tmp/links"
links wiki/index.md > "$tmp/indexed"

rc=0
report() { if [ -s "$2" ]; then echo "## $1"; sed 's/^/- /' "$2"; rc=1; fi; }

comm -13 "$tmp/slugs" "$tmp/links"   > "$tmp/broken";    report "Broken links (target page missing)" "$tmp/broken"
comm -23 "$tmp/slugs" "$tmp/indexed" > "$tmp/unindexed"; report "Pages missing from wiki/index.md" "$tmp/unindexed"

: > "$tmp/orphans"
while read -r s; do
  grep -rqF --include='*.md' --exclude=index.md "[[$s" wiki/sources wiki/decisions wiki/entities wiki/concepts wiki/notes projects/*.md || echo "$s" >> "$tmp/orphans"
done < "$tmp/slugs"
report "Orphans (no inbound links besides index)" "$tmp/orphans"

: > "$tmp/skills"
for d in skills/*/; do n=$(basename "$d"); case $n in ws-project-*) continue;; esac; grep -qF "($n/SKILL.md)" skills/index.md || echo "$n" >> "$tmp/skills"; done
report "Skills missing from skills/index.md" "$tmp/skills"

# project skills: tracked source must be exposed, card must point at it (fix: tools/project-skill-link.sh)
: > "$tmp/pskills"
for src in projects/ws_*.skill.md; do [ -e "$src" ] || continue; n=$(basename "$src" .skill.md); n=${n#ws_}
  cmp -s "$src" "skills/ws-project-$n/SKILL.md" || echo "$src → skills/ws-project-$n/SKILL.md missing or stale" >> "$tmp/pskills"
  grep -q "^skill: *ws-project-$n" "projects/ws_$n.md" 2>/dev/null || echo "projects/ws_$n.md lacks 'skill: ws-project-$n'" >> "$tmp/pskills"
done
for d in skills/ws-project-*/; do [ -d "$d" ] || continue; n=${d#skills/ws-project-}; n=${n%/}
  [ -f "projects/ws_$n.skill.md" ] || echo "$d has no source projects/ws_$n.skill.md" >> "$tmp/pskills"; done
report "Project skills out of sync" "$tmp/pskills"

: > "$tmp/cards"
for c in projects/ws_*.md; do [ -e "$c" ] || continue; case $c in *.skill.md) continue;; esac; n=$(basename "$c"); grep -qF "($n)" projects/index.md || echo "$n" >> "$tmp/cards"; done
report "Project cards missing from projects/index.md" "$tmp/cards"

: > "$tmp/tasks"
for d in work/*/*/; do [ -d "$d" ] || continue; t=${d#work/}; t=${t%/}; grep -qF "($t/)" work/index.md || echo "$t" >> "$tmp/tasks"; done
report "Task dirs missing from work/index.md" "$tmp/tasks"

: > "$tmp/nohead"
find wiki -path wiki/raw -prune -o -name '*.md' ! -name index.md -print | sort | while read -r f; do
  head -1 "$f" | grep -q '^---$' && grep -q '^\*\*TL;DR:\*\*' "$f" || echo "$f" >> "$tmp/nohead"
done
report "Pages without frontmatter or TL;DR" "$tmp/nohead"

# every tool exists as a pair: tools/<name>.sh (bash fallback) + tools/<name>.mjs (node)
: > "$tmp/twins"
for f in tools/*.sh; do n=$(basename "$f" .sh); [ -f "tools/$n.mjs" ] || echo "tools/$n.sh has no tools/$n.mjs" >> "$tmp/twins"; done
for f in tools/*.mjs; do n=$(basename "$f" .mjs); case $n in _*) continue;; esac; [ -f "tools/$n.sh" ] || echo "tools/$n.mjs has no tools/$n.sh" >> "$tmp/twins"; done
report "Tools without a .sh/.mjs twin" "$tmp/twins"

[ $rc -eq 0 ] && echo "lint: clean"
exit $rc

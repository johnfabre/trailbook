#!/usr/bin/env bash
# Mechanical size/risk gate for the trivial-change path. Run AFTER the main agent's edit, before review.
# Usage: tools/trivial-gate.sh <repo-path> [max-files=2] [max-lines=20]
# Counts the working tree vs HEAD (tracked + untracked, nothing staged or changed).
# Last lines of output (read only these):
#   STATUS: OK | PROMOTE
#   REASONS: <semicolon list, or ->
#   DIFF: <files> files, <lines> lines
set -uo pipefail
repo=${1:?repo path}; max_files=${2:-2}; max_lines=${3:-20}
# Paths that are never trivial, whatever the size (schema, API contracts, auth, money, deps, CI, infra).
risky='(migrat|schema|openapi|swagger|\.proto$|\.graphql$|\.sql$|auth|security|permission|payment|billing|secret|\.env|package-lock\.json$|yarn\.lock$|pnpm-lock\.yaml$|Cargo\.lock$|go\.sum$|poetry\.lock$|\.github/workflows/|Dockerfile|docker-compose|terraform|\.tf$)'

git -C "$repo" rev-parse --verify -q HEAD >/dev/null || { echo "STATUS: PROMOTE"; echo "REASONS: no HEAD in $repo"; echo "DIFF: ?"; exit 0; }

# Tracked changes vs HEAD, plus untracked files (counted as all-added), without touching the index.
numstat=$(
  git -C "$repo" diff HEAD --numstat
  git -C "$repo" ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
    if grep -Iq . "$repo/$f" 2>/dev/null || [ ! -s "$repo/$f" ]; then
      printf '%s\t0\t%s\n' "$(wc -l < "$repo/$f" | tr -d ' ')" "$f"
    else printf -- '-\t-\t%s\n' "$f"; fi
  done
)

reasons=()
files=0; lines=0
while IFS=$'\t' read -r add del path; do
  [ -n "${path:-}" ] || continue
  files=$((files + 1))
  if [ "$add" = "-" ]; then reasons+=("binary: $path"); continue; fi
  lines=$((lines + add + del))
  if grep -qiE "$risky" <<<"$path"; then reasons+=("risky path: $path"); fi
done <<<"$numstat"

[ "$files" -eq 0 ] && reasons+=("empty diff")
[ "$files" -gt "$max_files" ] && reasons+=("files $files > $max_files")
[ "$lines" -gt "$max_lines" ] && reasons+=("lines $lines > $max_lines")

if [ "${#reasons[@]}" -eq 0 ]; then echo "STATUS: OK"; echo "REASONS: -"
else echo "STATUS: PROMOTE"; ( IFS=';'; echo "REASONS: ${reasons[*]}" ); fi
echo "DIFF: $files files, $lines lines"

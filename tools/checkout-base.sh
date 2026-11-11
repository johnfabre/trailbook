#!/usr/bin/env bash
# Put a project repo on its default branch, pulled to the latest origin — without losing anything.
#
# Fast path: tree clean, no git operation in progress → fetch, switch <base>, pull --ff-only.
# Otherwise RESCUE, in this order (nothing is ever discarded before it is saved):
#   1. Local backup (never pushed): patch of all tracked changes + tarball of untracked files
#      → .trailbook/rescue/<project>/<stamp>/   (gitignored in the workspace)
#   2. Rebase / cherry-pick / revert in progress → abort it (backup + note keep the partial state).
#      Merge in progress → `merge --quit` (tree kept), committed as-is (conflict markers included) on the rescue branch.
#   3. Secret-looking untracked files (.env, *.pem, *.key, id_*, credentials*, …) → stashed locally, NOT pushed.
#   4. Everything else → committed on branch rescue/<stamp>-<from>, pushed, draft PR to <base>.
#      Commit impossible → git stash (noted).
#   5. Switch to <base> (forced only as a last resort — everything is backed up by then).
#   6. Local <base> has commits not on origin → saved on rescue/<stamp>-local-<base> (pushed, draft PR),
#      then <base> is reset to origin/<base>.
#   7. Note → work/<project>/<stamp>-rescue/rescue.md + line in work/index.md.
#
# Usage: tools/checkout-base.sh <project-name> [base-branch]   (base defaults to the card's `branch:`)
# Last lines of output: STATUS: CLEAN | RESCUED | FAILED, NOTE: <path>, FLAGS: <list>
set -uo pipefail
ws=$(cd "$(dirname "$0")/.." && pwd)
name=${1:?usage: checkout-base.sh <project> [base]}
R="$ws/projects/$name"; card="$ws/projects/ws_$name.md"
base=${2:-$(sed -n '/^---$/,/^---$/p' "$card" 2>/dev/null | sed -n 's/^branch:[[:space:]]*//p' | sed 's/[[:space:]]*#.*//' | head -1)}
[ -d "$R/.git" ] || { echo "STATUS: FAILED"; echo "REASON: $R is not a git checkout"; exit 1; }
[ -n "$base" ] || { echo "STATUS: FAILED"; echo "REASON: no base branch (card branch: missing)"; exit 1; }
g() { git -C "$R" "$@"; }
gp() { (cd "$R" && [ -e "$(git rev-parse --git-path "$1")" ]); }   # git-path is relative to the repo

g fetch -q origin --prune || echo "warn: fetch failed (offline?) — continuing with local refs"
dirty=$(g status --porcelain)
op=""; gp MERGE_HEAD && op=merge; gp rebase-merge && op=rebase; gp rebase-apply && op=rebase
gp CHERRY_PICK_HEAD && op=cherry-pick; gp REVERT_HEAD && op=revert

sync_base() {  # on a clean tree: switch + pull; handle a diverged local base
  g switch -q "$base" 2>/dev/null || g switch -q -c "$base" --track "origin/$base" 2>/dev/null || return 1
  if g rev-parse -q --verify "origin/$base" >/dev/null; then
    ahead=$(g rev-list --count "origin/$base..$base")
    if [ "$ahead" -gt 0 ]; then return 2; fi
    g pull -q --ff-only origin "$base" || return 1
  fi
  return 0
}

if [ -z "$dirty" ] && [ -z "$op" ]; then
  sync_base; rc=$?
  if [ $rc -eq 0 ]; then echo "on $base @ $(g rev-parse --short HEAD) (up to date with origin)"; echo "STATUS: CLEAN"; exit 0; fi
fi

# ---------- rescue ----------
stamp=$(date +%Y-%m-%d-%H%M%S)
from=$(g branch --show-current); from=${from:-detached-$(g rev-parse --short HEAD)}
slug=$(printf '%s' "$from" | tr '/ ' '--' | tr -cd 'A-Za-z0-9._-')
bk="$ws/.trailbook/rescue/$name/$stamp"; mkdir -p "$bk"
taskrel="$name/$stamp-rescue"; task="$ws/work/$taskrel"; mkdir -p "$task"
note="$task/rescue.md"; flags=(); prs=(); log=()
say() { log+=("- $*"); echo "$*"; }

{ g status --porcelain=v2 -b; echo; g stash list; } > "$bk/status.txt"
g diff HEAD --binary > "$bk/tracked.patch" 2>/dev/null || g diff --binary > "$bk/tracked.patch"
mapfile -t untracked < <(g ls-files --others --exclude-standard)
[ ${#untracked[@]} -gt 0 ] && (cd "$R" && tar -czf "$bk/untracked.tgz" -- "${untracked[@]}")
say "local backup (not pushed): ${bk#$ws/}"
mapfile -t conflicted < <(g diff --name-only --diff-filter=U)
[ ${#conflicted[@]} -gt 0 ] && flags+=(conflicts)

case "$op" in
  rebase|cherry-pick|revert) g "$op" --abort && say "aborted in-progress $op (partial state in backup)"; flags+=("$op-aborted") ;;
  merge) mh=$(g rev-parse --short MERGE_HEAD)
         g merge --quit && say "merge of $mh into $from was in progress → quit (working tree kept) and committed as-is, conflict markers included, on the rescue branch"
         flags+=(merge-in-progress) ;;
esac

push_pr() {  # $1 branch, $2 title
  if g push -q -u origin "$1" 2>/dev/null; then
    url=$(cd "$R" && gh pr create --draft --base "$base" --head "$1" --title "$2" \
          --body "Automatic rescue by Trailbook before switching to \`$base\`. Nothing here was reviewed — see the workspace note \`work/$taskrel/rescue.md\`. Close without merging once resolved." 2>/dev/null)
    if [ -n "$url" ]; then prs+=("$url"); say "draft PR: $url"; else say "pushed $1 (no PR created — open one manually)"; flags+=(no-pr); fi
  else say "push of $1 failed — branch kept locally"; flags+=(not-pushed); fi
}

if [ -n "$(g status --porcelain)" ]; then
  # secret-looking untracked files: keep local only
  mapfile -t sensitive < <(printf '%s\n' "${untracked[@]}" | grep -Ei '(^|/)(\.env(\..*)?|.*\.(pem|key|p12|pfx|jks)|id_(rsa|ecdsa|ed25519)(\.pub)?|credentials.*|.*secret.*|.*\.kdbx)$' || true)
  if [ ${#sensitive[@]} -gt 0 ] && [ -n "${sensitive[0]}" ]; then
    g stash push -q -u -m "trailbook rescue $stamp: sensitive files (local only)" -- "${sensitive[@]}" \
      && say "stashed ${#sensitive[@]} secret-looking file(s) locally, not pushed: ${sensitive[*]}" && flags+=(sensitive-stashed)
  fi
  rb="rescue/$stamp-$slug"
  if g switch -q -c "$rb" && g add -A && g -c core.hooksPath=/dev/null commit -q --no-verify -m "rescue: leftover work on $from before switching to $base"; then
    say "committed leftovers on $rb"; flags+=(leftovers)
    push_pr "$rb" "rescue: leftover work on $from ($stamp)"
  else
    g stash push -q -u -m "trailbook rescue $stamp: leftovers from $from" && say "commit failed → stashed leftovers (git stash list)"; flags+=(stashed)
  fi
fi

sync_base; rc=$?
if [ $rc -eq 1 ]; then
  g switch -q -f "$base" && say "forced switch to $base (everything backed up first)" && flags+=(forced-switch)
  g pull -q --ff-only origin "$base" 2>/dev/null; sync_base; rc=$?
fi
if [ $rc -eq 2 ]; then
  lb="rescue/$stamp-local-$base"
  g branch "$lb" "$base" && say "local $base had $(g rev-list --count "origin/$base..$base") commit(s) not on origin → saved on $lb"
  flags+=(base-diverged); push_pr "$lb" "rescue: unpushed local commits on $base ($stamp)"
  g reset -q --hard "origin/$base" && say "reset $base to origin/$base"
fi

head=$(g rev-parse --short HEAD 2>/dev/null); cur=$(g branch --show-current)
if [ "$cur" = "$base" ] && [ -z "$(g status --porcelain)" ] && { ! g rev-parse -q --verify "origin/$base" >/dev/null || [ "$(g rev-parse HEAD)" = "$(g rev-parse "origin/$base")" ]; }; then
  status=RESCUED; say "now on $base @ $head, clean, matches origin"
else
  status=FAILED; say "could not reach a clean $base (on '$cur', see git status)"
fi

{
  echo "---"; echo "title: Rescue before checking out $base ($name)"; echo "type: rescue"; echo "project: $name"
  echo "date: $(date +%Y-%m-%d)"; echo "status: needs-review"; echo "from: $from"; echo "flags: [${flags[*]}]"; echo "---"
  echo "**TL;DR:** couldn't switch \`$name\` to \`$base\` cleanly; leftovers were saved (${flags[*]:-none}) and the repo was moved to \`$base\`. Review and close the rescue PR(s)."
  echo; echo "## What happened"; printf '%s\n' "${log[@]}"
  echo; echo "## State before rescue"; echo '```'; head -40 "$bk/status.txt"; echo '```'
  [ ${#conflicted[@]} -gt 0 ] && { echo; echo "## Conflicted files"; printf -- '- %s\n' "${conflicted[@]}"; }
  echo; echo "## Recover"
  echo "- Rescue PRs: ${prs[*]:-none}"
  echo "- Local backup (this machine only): \`${bk#$ws/}\` — \`git apply tracked.patch\`, \`tar -xzf untracked.tgz\`"
  echo "- Stashes: \`git -C projects/$name stash list\` (look for \"trailbook rescue $stamp\")"
} > "$note"
grep -q '^## Open' "$ws/work/index.md" 2>/dev/null && \
  sed -i "/^## Open/a - $name · [$stamp-rescue]($taskrel/) — rescue before checkout of $base (${flags[*]:-none}) · rescue · needs-review · doc: rescue.md · PR: ${prs[*]:-—}" "$ws/work/index.md"

echo "STATUS: $status"; echo "NOTE: work/$taskrel/rescue.md"; echo "FLAGS: ${flags[*]:-none}"
[ "$status" = FAILED ] && exit 1 || exit 0

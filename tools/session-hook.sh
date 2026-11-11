#!/usr/bin/env bash
# Session hook for the wiki-filing reminder. Works in Claude Code and GitHub Copilot
# (Copilot reads the same .claude/settings.json; PascalCase events get snake_case fields).
#   start → reminder that the wiki is only updated when the session is closed deliberately,
#           plus a warning listing earlier sessions that ended without being filed.
#   stop  → remember this session's transcript path (Copilot's SessionEnd payload has none).
#   end   → if this session was never filed and had real conversation (≥ 3 user prompts),
#           record it in .trailbook/unfiled-sessions.
# Usage (from settings.json): tools/session-hook.sh start|stop|end   (hook JSON on stdin)
# Pure bash + grep/sed (no jq, no python), so the reminder works on a stock Git Bash / macOS / Linux.
# Only `end` needs perl (via tools/session-extract.sh), which ships with all three.
# Fail-safe by design: a hook must never break anyone's session. Missing tools or any error → exit 0 silently
# (the AGENTS.md rule still makes the agent give the reminder).
set -uo pipefail
trap 'exit 0' ERR
cd "$(dirname "$0")/.." || exit 0
state=.trailbook/unfiled-sessions
input=$(cat)
soh=$(printf '\001'); tab=$(printf '\t')

# jget <key>… → string value of the first of these keys found in the hook payload ('' if none).
# The payload is small, flat JSON; a copy of a key inside another string can't match (its quotes are escaped).
jget() {
  local k m
  for k in "$@"; do
    m=$(printf '%s' "$input" | grep -oE "\"$k\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" | head -n 1) || true
    [ -n "$m" ] || continue
    # strip `"key":"` and the closing quote, then unescape: \\ → \ (Windows paths), \" → ", \/ → /
    printf '%s' "$m" | sed -e 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//' -e 's/"$//' \
      -e "s/\\\\\\\\/$soh/g" -e 's/\\"/"/g' -e 's#\\/#/#g' -e "s/$soh/\\\\/g"
    return 0
  done
}
# jstr <text> → JSON string literal
jstr() {
  local esc out="" line first=1
  esc=$(printf '%s' "$1" | tr -d '\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g")
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$first" = 1 ] || out="$out\\n"; first=0; out="$out$line"
  done <<<"$esc"
  printf '"%s"' "$out"
}

sid=$(jget session_id sessionId)
tp=$(jget transcript_path transcriptPath)
src=$(jget source); src=${src:-startup}
mode=${1:-start}
# Claude Code sets CLAUDE_PROJECT_DIR for hooks; Copilot doesn't.
harness=copilot; [ -n "${CLAUDE_PROJECT_DIR:-}" ] && harness=claude

filed() { grep -rqsF "session: $1" wiki/raw/sessions/; }

case "$mode" in
stop)
  [ -n "$sid" ] && [ -n "$tp" ] || exit 0
  mkdir -p .trailbook/transcripts && printf '%s\n' "$tp" > ".trailbook/transcripts/$sid"
  [ "$harness" = claude ] || echo '{}'
  exit 0 ;;
end)
  [ -n "$sid" ] || exit 0
  filed "$sid" && exit 0
  [ -z "$tp" ] && [ -f ".trailbook/transcripts/$sid" ] && tp=$(cat ".trailbook/transcripts/$sid")
  ref=${tp:-$sid}
  command -v perl >/dev/null 2>&1 || exit 0
  prompts=$(tools/session-extract.sh "$ref" 2>/dev/null | grep -c '^\*\*User:\*\*' || true)
  [ "${prompts:-0}" -ge 3 ] || exit 0
  mkdir -p .trailbook
  grep -qsF "$sid" "$state" || echo "$sid $(date +%Y-%m-%d) prompts=$prompts ${tp:+transcript=$tp}" >> "$state"
  exit 0 ;;
esac

# start
[ "$src" = compact ] && exit 0
if [ -s "$state" ]; then
  tmp=$(mktemp); while read -r id rest; do filed "$id" || echo "$id $rest"; done < "$state" > "$tmp"; mv "$tmp" "$state"
fi
n=$( [ -s "$state" ] && wc -l < "$state" || echo 0 )
msg="📚 Trailbook: the wiki is only updated when you END this session deliberately — say \"done\" (or /session-close) before closing. Closing without it files nothing."
ctx="Workspace reminder: wiki filing happens only via skill session-close when the user says the session is done. Tell the user this in one line at the top of your first reply (they may not see hook messages), and again in one line whenever a unit of work finishes."
if [ "$n" -gt 0 ]; then
  msg="$msg
⚠️ $n earlier session(s) ended without filing — say \"file unfiled sessions\" to ingest them (ids in $state)."
  ctx="$ctx Unfiled earlier sessions are listed in $state ('<session-id> <date> prompts=<n> [transcript=<path>]' per line); mention them and offer to file them via session-close."
fi
if [ "$harness" = claude ]; then
  printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(jstr "$msg")" "$(jstr "$ctx")"
else
  printf '{"additionalContext":%s}\n' "$(jstr "$msg

$ctx")"   # Copilot consumes only additionalContext on sessionStart
fi

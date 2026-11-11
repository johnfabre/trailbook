#!/usr/bin/env bash
# Open a vault file in Obsidian through the obsidian:// URI (works when there is no `obsidian` binary on PATH).
# Pure bash — no python/jq. Vault = this workspace (vault name = workspace folder name).
# Usage: tools/obsidian-open.sh <vault-relative path>     e.g. tools/obsidian-open.sh views/2026-11-08-plan.md
#        tools/obsidian-open.sh --print <path>            only print the URI
set -uo pipefail
print=0; [ "${1:-}" = --print ] && { print=1; shift; }
file=${1:?usage: obsidian-open.sh [--print] <vault-relative path>}
ws=$(cd "$(dirname "$0")/.." && pwd)

urlenc() {   # percent-encode everything except unreserved characters, byte by byte (UTF-8 safe)
  local LC_ALL=C s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9._~-]) out="$out$c" ;;
      *) out="$out$(printf '%%%02X' "$(( $(printf '%d' "'$c") & 255 ))")" ;;
    esac
  done
  printf '%s' "$out"
}

uri="obsidian://open?vault=$(urlenc "$(basename "$ws")")&file=$(urlenc "${file#./}")"
[ "$print" = 1 ] && { echo "$uri"; exit 0; }

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) rundll32.exe url.dll,FileProtocolHandler "$uri" ;;   # Git Bash; `start` would choke on the &
  Darwin) open "$uri" ;;
  *) if grep -qi microsoft /proc/version 2>/dev/null && command -v rundll32.exe >/dev/null 2>&1; then
       rundll32.exe url.dll,FileProtocolHandler "$uri"                      # WSL → Obsidian on the Windows side
     else xdg-open "$uri"; fi ;;
esac >/dev/null 2>&1

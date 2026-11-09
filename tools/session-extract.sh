#!/usr/bin/env bash
# Turn an agent session transcript into a compact, code-free markdown source for wiki ingest.
# Supports: Claude Code (~/.claude/projects/*/<id>.jsonl) and GitHub Copilot in VS Code
# (~/.config/Code*/User/workspaceStorage/*/chatSessions/<id>.jsonl). Format is auto-detected.
# Keeps: user messages, assistant prose, one-line summaries of actions (files edited, commands, subagents).
# Drops: tool outputs, thinking, system reminders, file contents, code. Redacts obvious secrets.
# Usage: tools/session-extract.sh [session-id | path.jsonl] [-o out.md]
#   no arg → most recently modified transcript (either tool) belonging to this workspace
set -euo pipefail
ws=$(cd "$(dirname "$0")/.." && pwd)
src=""; out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) src="$1"; shift;; esac; done
python3 -I - "$ws" "$src" > "${out:-/dev/stdout}" <<'PY'
import glob, json, os, re, sys
from urllib.parse import unquote
ws, src = sys.argv[1], sys.argv[2]
HOME = os.path.expanduser('~')
CLAUDE = glob.glob(f'{HOME}/.claude/projects/*/*.jsonl')
VSCODE_USER = [f'{HOME}/.config/Code*/User',                          # Linux
               f'{HOME}/Library/Application Support/Code*/User',      # macOS
               os.path.join(os.environ.get('APPDATA', '~nowhere~'), 'Code*', 'User')]  # Windows
VSCODE = [p for base in VSCODE_USER for p in glob.glob(f'{base}/workspaceStorage/*/chatSessions/*.jsonl')]

def vscode_ws(path):  # workspace folder a VS Code chat session belongs to
    try:
        meta = json.load(open(os.path.join(os.path.dirname(os.path.dirname(path)), 'workspace.json')))
        folder = unquote(meta.get('folder', '').replace('file://', ''))
        return folder[1:] if re.match(r'^/[A-Za-z]:', folder) else folder  # file:///C:/… on Windows
    except (OSError, ValueError): return ''
def claude_ws(path):
    try:
        for line in open(path):
            cwd = json.loads(line).get('cwd')
            if cwd: return cwd
    except (OSError, ValueError): pass
    return ''
def resolve():
    if src and os.path.isfile(src): return src
    if src:
        hits = [p for p in CLAUDE + VSCODE if os.path.basename(p) == f'{src}.jsonl']
        if hits: return hits[0]
        sys.exit(f'transcript not found for session {src}')
    # same workspace; Claude transcripts of a renamed folder still match by basename
    def mine(p):
        w = vscode_ws(p) if p in VSCODE else claude_ws(p)
        return w and (os.path.realpath(w) == ws or os.path.basename(w) == os.path.basename(ws))
    cands = sorted(CLAUDE + VSCODE, key=os.path.getmtime, reverse=True)
    for p in cands[:200]:
        if mine(p): return p
    sys.exit('no transcript found for this workspace')

SECRET = [r'sk-[A-Za-z0-9_-]{16,}', r'gh[pousr]_[A-Za-z0-9]{20,}', r'AKIA[0-9A-Z]{16}', r'xox[abpr]-[A-Za-z0-9-]{10,}',
          r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
          r'(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+']
def redact(s):
    for p in SECRET: s = re.sub(p, '[REDACTED]', s)
    return s
def clean_user(s):
    s = re.sub(r'<system-reminder>[\s\S]*?</system-reminder>', '', s)
    s = re.sub(r'<(local-command-[a-z]+|command-[a-z]+)>[\s\S]*?</\1>', '', s)
    s = re.sub(r'<pasted_content[^>]*>([\s\S]*?)</pasted_content[^>]*>',
               lambda m: '[pasted: ' + (m.group(1).strip()[:1500] + (' …(truncated)' if len(m.group(1)) > 1500 else '')) + ']', s)
    s = re.sub(r'```[\s\S]*?```', '[code block omitted]', s)
    return s.strip()
def clean_assistant(s):
    s = re.sub(r'```(mermaid)?[\s\S]*?```', lambda m: '[diagram omitted]' if m.group(1) else '[code omitted]', s)
    return s.strip()

turns, acts, meta = [], [], {}
def flush():
    if acts: turns.append('Actions: ' + '; '.join(dict.fromkeys(acts))); acts.clear()
def say(who, s):
    if s: flush(); turns.append(f'**{who}:** {s}')

def claude(path):
    def action(b):
        n, i = b.get('name', '?'), b.get('input') or {}
        if n in ('Edit', 'Write', 'NotebookEdit'): return f"{n} {i.get('file_path', '')}"
        if n == 'Bash': return f"Bash: {i.get('description') or (i.get('command', '').splitlines() or [''])[0][:100]}"
        if n == 'Agent': return f"Subagent {i.get('subagent_type', 'general')} [{i.get('model', 'default')}]: {i.get('description', '')}"
        if n == 'Skill': return f"Skill {i.get('skill')}"
        if n in ('Read', 'Grep', 'Glob', 'ToolSearch', 'TodoWrite'): return None
        return n
    meta['tool'] = 'claude-code'
    for line in open(path):
        try: o = json.loads(line)
        except ValueError: continue
        if o.get('type') not in ('user', 'assistant') or o.get('isSidechain') or o.get('isMeta'): continue
        meta.setdefault('start', o.get('timestamp')); meta['end'] = o.get('timestamp')
        meta.setdefault('cwd', o.get('cwd')); meta.setdefault('session', o.get('sessionId'))
        c = (o.get('message') or {}).get('content')
        for b in ([{'type': 'text', 'text': c}] if isinstance(c, str) else (c or [])):
            t = b.get('type')
            if o['type'] == 'user' and t == 'text': say('User', clean_user(b.get('text', '')))
            elif o['type'] == 'assistant' and t == 'text': say('Assistant', clean_assistant(b.get('text', '')))
            elif o['type'] == 'assistant' and t == 'tool_use':
                a = action(b)
                if a: acts.append(a)

def vscode(path):
    # incremental patch log: kind 0 = initial state, 1 = set value at path k, 2 = append (optionally truncate at i), 3 = delete
    st = {}
    for line in open(path):
        try: o = json.loads(line)
        except ValueError: continue
        if o.get('kind') == 0: st = o.get('v') or {}; continue
        k = o.get('k') or []
        try:
            parent = st
            for p in k[:-1]: parent = parent[p]
            if o['kind'] == 1: parent[k[-1]] = o.get('v')
            elif o['kind'] == 2:
                arr = parent[k[-1]]; v = o.get('v', [])
                if o.get('i') is not None: del arr[o['i']:]
                arr.extend(v if isinstance(v, list) else [v])
            elif o['kind'] == 3: del parent[k[-1]]
        except (KeyError, IndexError, TypeError): continue
    meta.update(tool='copilot-vscode', session=st.get('sessionId'), cwd=vscode_ws(path))
    reqs = [r for r in st.get('requests', []) if not r.get('hiddenFromTranscript')]
    import datetime
    iso = lambda ms: datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).isoformat() if isinstance(ms, (int, float)) else ms
    if reqs: meta['start'], meta['end'] = iso(reqs[0].get('timestamp')), iso(reqs[-1].get('timestamp'))
    def val(m): return (m or {}).get('value', '') if isinstance(m, dict) else (m or '')
    for r in reqs:
        say('User', clean_user(val(r.get('message')) or (r.get('message') or {}).get('text', '')))
        md = []
        for p in r.get('response', []):
            kind = p.get('kind')
            if kind is None and 'value' in p: md.append(p['value'])
            elif kind == 'toolInvocationSerialized':
                if md: say('Assistant', clean_assistant(''.join(md))); md = []
                tid = p.get('toolId', '')
                if tid in ('manage_todo_list', 'copilot_readFile', 'read_file', 'copilot_findTextInFiles', 'grep_search', 'file_search'): continue
                msg = val(p.get('pastTenseMessage')) or val(p.get('invocationMessage'))
                msg = re.sub(r'\s+', ' ', msg)[:120]
                acts.append(f'{tid}: {msg}' if msg else tid)
            elif kind == 'textEditGroup':
                uri = (p.get('uri') or {}).get('path') or (p.get('uri') or {}).get('fsPath', '')
                if uri: acts.append(f'Edit {uri}')
        if md: say('Assistant', clean_assistant(''.join(md)))

path = resolve()
first = open(path).readline()
(vscode if '"kind"' in first and '"requests"' in first else claude)(path)
flush()
print('---')
for key in ('tool', 'session', 'cwd', 'start', 'end'): print(f'{key}: {meta.get(key)}')
print('type: session-transcript\n---\n')
print(redact('\n\n'.join(turns)))
PY

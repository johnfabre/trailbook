#!/usr/bin/env node
// Turn an agent session transcript into a compact, code-free markdown source for wiki ingest.
// Node twin of tools/session-extract.sh (same output).
// Supports: Claude Code (~/.claude/projects/*/<id>.jsonl) and GitHub Copilot in VS Code
// (~/.config/Code*/User/workspaceStorage/*/chatSessions/<id>.jsonl). Format is auto-detected.
// Keeps: user messages, assistant prose, one-line summaries of actions (files edited, commands, subagents).
// Drops: tool outputs, thinking, system reminders, file contents, code. Redacts obvious secrets.
// Usage: node tools/session-extract.mjs [session-id | path.jsonl] [-o out.md]
//   no arg → most recently modified transcript (either tool) belonging to this workspace
import fs from 'node:fs';
import os from 'node:os';
import { ws as WS, isMain, isFile, isDir, ls, slashes } from './_lib.mjs';

// ---- helpers ----
const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
const isRef = (x) => x !== null && typeof x === 'object';
const has = (x) => x !== null && x !== undefined && (isRef(x) || String(x).length > 0);   // non-empty scalar / any object
const scalar = (x) => (x === null || x === undefined || isRef(x) ? undefined : String(x));
const basename = (p) => slashes(p).replace(/\/+$/, '').replace(/.*\//, '');
const dirname = (p) => { const s = slashes(p).replace(/\/+$/, ''); return s.includes('/') ? s.replace(/\/[^/]*$/, '') : '.'; };
const fold = (p) => (process.platform === 'win32' ? p.toLowerCase() : p);
const realp = (p) => { try { return fold(slashes(fs.realpathSync(p))); } catch { return fold(slashes(p)); } };
const parse = (s) => { try { return [true, JSON.parse(s)]; } catch { return [false, undefined]; } };
function linesOf(p) {
  let t;
  try { t = fs.readFileSync(p, 'utf8'); } catch { return []; }
  const l = t.split('\n');
  if (l[l.length - 1] === '') l.pop();
  return l;
}

/** Expand a path pattern whose segments may contain `*` (enough for the fixed patterns below). */
function glob(pattern) {
  let acc = [''];
  const segs = slashes(pattern).split('/');
  segs.forEach((seg, i) => {
    const next = [];
    for (const base of acc) {
      if (!seg.includes('*')) {
        const p = i === 0 ? seg : `${base}/${seg}`;
        if (i < segs.length - 1 || fs.existsSync(p)) next.push(p);
      } else {
        const re = new RegExp(`^${seg.split('*').map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*')}$`);
        for (const n of ls(base || '/', re)) if (!n.startsWith('.') || seg.startsWith('.')) next.push(`${base}/${n}`);
      }
    }
    acc = next;
  });
  return acc;
}

// ---- locate transcripts ----
function transcripts() {
  // Git Bash: HOME (/c/Users/x) and USERPROFILE (C:\Users\x) are usually the same folder, but HOME can be remapped
  const seen = new Set();
  const homes = [process.env.HOME, process.env.USERPROFILE, os.homedir()]
    .filter((h) => h && isDir(h)).map(slashes)
    .filter((h) => { const r = realp(h); return seen.has(r) ? false : seen.add(r); });
  const claudeRoots = homes.map((h) => `${h}/.claude`);
  if (process.env.CLAUDE_CONFIG_DIR) claudeRoots.push(slashes(process.env.CLAUDE_CONFIG_DIR));
  const claude = [...new Set(claudeRoots.flatMap((r) => glob(`${r}/projects/*/*.jsonl`)))];
  const vsUser = homes.flatMap((h) => [`${h}/.config/Code*/User`, `${h}/Library/Application Support/Code*/User`, `${h}/AppData/Roaming/Code*/User`]);   // Linux, macOS, Windows
  if (process.env.APPDATA) vsUser.push(`${slashes(process.env.APPDATA)}/Code*/User`);
  const vscode = [...new Set(vsUser.flatMap((u) => glob(`${u}/workspaceStorage/*/chatSessions/*.jsonl`)))];
  return { claude, vscode };
}

function vscodeWs(p) {   // workspace folder a VS Code chat session belongs to
  let txt;
  try { txt = fs.readFileSync(`${dirname(dirname(p))}/workspace.json`, 'utf8'); } catch { return ''; }
  const [ok, meta] = parse(txt);
  if (!ok || !isObj(meta)) return '';
  let folder = typeof meta.folder === 'string' ? meta.folder : '';
  folder = folder.replaceAll('file://', '');
  try { folder = decodeURIComponent(folder); } catch { /* keep raw */ }
  return folder.replace(/^\/(?=[A-Za-z]:)/, '');   // file:///C:/… on Windows
}
function claudeWs(p) {
  for (const line of linesOf(p)) {
    const [ok, o] = parse(line);
    if (!ok) return '';
    const cwd = isObj(o) ? o.cwd : undefined;
    if (typeof cwd === 'string' && cwd.length) return cwd;
  }
  return '';
}
function resolve(ws, src) {
  if (src && isFile(src)) return src;
  const { claude, vscode } = transcripts();
  if (src) {
    for (const p of [...claude, ...vscode]) if (basename(p) === `${src}.jsonl`) return p;
    throw new Error(`transcript not found for session ${src}`);
  }
  // same workspace; Claude transcripts of a renamed folder still match by basename
  const isVs = new Set(vscode);
  const mt = (p) => { try { return fs.statSync(p).mtimeMs; } catch { return 0; } };
  const cands = [...claude, ...vscode].map((p) => [p, mt(p)]).sort((a, b) => b[1] - a[1]).slice(0, 200);
  const wsr = realp(ws);
  for (const [p] of cands) {
    const w = isVs.has(p) ? vscodeWs(p) : claudeWs(p);
    if (!w) continue;
    if (realp(w) === wsr || fold(basename(w)) === fold(basename(ws))) return p;
  }
  throw new Error('no transcript found for this workspace');
}

// ---- cleaning ----
const SECRET = [/sk-[A-Za-z0-9_-]{16,}/g, /gh[pousr]_[A-Za-z0-9]{20,}/g, /AKIA[0-9A-Z]{16}/g, /xox[abpr]-[A-Za-z0-9-]{10,}/g,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
  /(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+/gi];
const redact = (s) => SECRET.reduce((t, re) => t.replace(re, '[REDACTED]'), s);
const strip = (s) => s.replace(/^\s+/, '').replace(/\s+$/, '');
const chars = (s, n) => { const c = Array.from(s); return [c.slice(0, n).join(''), c.length]; };   // by code point
function cleanUser(x) {
  let s = scalar(x);
  if (s === undefined) return '';
  s = s.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '');
  s = s.replace(/<(local-command-[a-z]+|command-[a-z]+)>[\s\S]*?<\/\1>/g, '');
  s = s.replace(/<pasted_content[^>]*>([\s\S]*?)<\/pasted_content[^>]*>/g, (_, body) => {
    const [head] = chars(strip(body), 1500);
    return `[pasted: ${head}${chars(body, 0)[1] > 1500 ? ' …(truncated)' : ''}]`;
  });
  s = s.replace(/```[\s\S]*?```/g, '[code block omitted]');
  return strip(s);
}
function cleanAssistant(x) {
  const s = scalar(x);
  if (s === undefined) return '';
  return strip(s.replace(/```(mermaid)?[\s\S]*?```/g, (_, m) => (m ? '[diagram omitted]' : '[code omitted]')));
}

/** Transcript at `file` → markdown (frontmatter + turns). */
export function render(file) {
  const turns = [];
  let acts = [];
  const meta = {};
  const flushActs = () => {
    if (!acts.length) return;
    turns.push(`Actions: ${[...new Set(acts)].join('; ')}`);
    acts = [];
  };
  const say = (who, s) => { if (!has(s)) return; flushActs(); turns.push(`**${who}:** ${s}`); };

  // ---- Claude Code transcript ----
  function claudeAction(b) {
    const n = b.name ?? '?';
    const i = isObj(b.input) ? b.input : {};
    const g = (k, d) => scalar(i[k]) ?? d;
    if (n === 'Edit' || n === 'Write' || n === 'NotebookEdit') return `${n} ${g('file_path', '')}`;
    if (n === 'Bash') {
      let d = g('description', '');
      if (!d.length) d = chars(g('command', '').split(/\r\n|[\n\r\x0b\x0c\x1c-\x1e\x85\u2028\u2029]/)[0] ?? '', 100)[0];
      return `Bash: ${d}`;
    }
    if (n === 'Agent') return `Subagent ${g('subagent_type', 'general')} [${g('model', 'default')}]: ${g('description', '')}`;
    if (n === 'Skill') return `Skill ${g('skill', 'None')}`;
    if (/^(?:Read|Grep|Glob|ToolSearch|TodoWrite)$/.test(n)) return undefined;
    return n;
  }
  function claude() {
    meta.tool = 'claude-code';
    for (const line of linesOf(file)) {
      const [ok, o] = parse(line);
      if (!ok || !isObj(o)) continue;
      const type = o.type ?? '';
      if (type !== 'user' && type !== 'assistant') continue;
      if (o.isSidechain || o.isMeta) continue;
      if (!('start' in meta)) meta.start = o.timestamp;
      meta.end = o.timestamp;
      if (!('cwd' in meta)) meta.cwd = o.cwd;
      if (!('session' in meta)) meta.session = o.sessionId;
      const c = isObj(o.message) ? o.message.content : undefined;
      const blocks = c === null || c === undefined ? [] : Array.isArray(c) ? c : isRef(c) ? [] : [{ type: 'text', text: c }];
      for (const b of blocks) {
        if (!isObj(b)) continue;
        const t = b.type ?? '';
        if (type === 'user' && t === 'text') say('User', cleanUser(b.text));
        else if (type === 'assistant' && t === 'text') say('Assistant', cleanAssistant(b.text));
        else if (type === 'assistant' && t === 'tool_use') { const a = claudeAction(b); if (has(a)) acts.push(a); }
      }
    }
  }

  // ---- GitHub Copilot (VS Code) chat session ----
  const isNum = (x) => !isRef(x) && x !== undefined && /^-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?$/.test(String(x));
  function iso(ms) {   // epoch milliseconds → ISO-8601 UTC
    if (!isNum(ms)) return ms;
    const n = Number(ms);
    const sec = Math.trunc(n / 1000);
    const us = Math.trunc((n - 1000 * sec) * 1000 + 0.5);
    return new Date(sec * 1000).toISOString().slice(0, 19) + (us ? `.${String(us).padStart(6, '0')}` : '') + '+00:00';
  }
  const val = (m) => (isObj(m) ? (m.value ?? '') : (m ?? ''));
  const isIdx = (a, k) => Array.isArray(a) && /^\d+$/.test(String(k)) && Number(k) < a.length;
  function vscode() {
    // incremental patch log: kind 0 = initial state, 1 = set value at path k, 2 = append (optionally truncate at i), 3 = delete
    let st = {};
    LINE: for (const line of linesOf(file)) {
      const [ok, o] = parse(line);
      if (!ok || !isObj(o)) continue;
      const kind = Number(o.kind ?? -1);
      if (kind === 0) { st = isRef(o.v) ? o.v : {}; continue; }
      const k = Array.isArray(o.k) ? [...o.k] : [];
      if (!k.length) continue;
      const last = k.pop();
      let parent = st;
      for (const p of k) {
        if (isObj(parent) && Object.hasOwn(parent, p)) parent = parent[p];
        else if (isIdx(parent, p)) parent = parent[p];
        else continue LINE;
      }
      const idx = isIdx(parent, last);
      if (!isObj(parent) && !idx) continue;
      if (kind === 1) parent[last] = o.v;
      else if (kind === 2) {
        const arr = parent[last];
        if (!Array.isArray(arr)) continue;
        const v = 'v' in o ? o.v : [];
        if (isIdx(arr, o.i)) arr.length = Number(o.i);
        if (Array.isArray(v)) arr.push(...v); else arr.push(v);
      } else if (kind === 3) { if (idx) parent.splice(Number(last), 1); else delete parent[last]; }
    }
    if (!isObj(st)) st = {};
    meta.tool = 'copilot-vscode'; meta.session = st.sessionId; meta.cwd = vscodeWs(file);
    const reqs = (Array.isArray(st.requests) ? st.requests : []).filter((r) => isObj(r) && !r.hiddenFromTranscript);
    if (reqs.length) { meta.start = iso(reqs[0].timestamp); meta.end = iso(reqs[reqs.length - 1].timestamp); }
    for (const r of reqs) {
      let m = val(r.message);
      if (!has(m)) m = isObj(r.message) ? r.message.text : undefined;
      say('User', cleanUser(m));
      let md = [];
      for (const p of Array.isArray(r.response) ? r.response : []) {
        if (!isObj(p)) continue;
        const kind = p.kind;
        if (kind === null || kind === undefined) { if (scalar(p.value) !== undefined) md.push(scalar(p.value)); }
        else if (kind === 'toolInvocationSerialized') {
          if (md.length) { say('Assistant', cleanAssistant(md.join(''))); md = []; }
          const tid = p.toolId ?? '';
          if (/^(?:manage_todo_list|copilot_readFile|read_file|copilot_findTextInFiles|grep_search|file_search)$/.test(tid)) continue;
          let msg = val(p.pastTenseMessage);
          if (!has(msg)) msg = val(p.invocationMessage);
          msg = isRef(msg) ? '' : chars(String(msg).replace(/\s+/g, ' '), 120)[0];
          acts.push(msg.length ? `${tid}: ${msg}` : tid);
        } else if (kind === 'textEditGroup') {
          let uri = isObj(p.uri) ? p.uri.path : undefined;
          if (!has(uri)) uri = isObj(p.uri) ? p.uri.fsPath : undefined;
          if (has(uri)) acts.push(`Edit ${uri}`);
        }
      }
      if (md.length) say('Assistant', cleanAssistant(md.join('')));
    }
  }

  const first = linesOf(file)[0] ?? '';
  if (first.includes('"kind"') && first.includes('"requests"')) vscode(); else claude();
  flushActs();
  let out = '---\n';
  for (const k of ['tool', 'session', 'cwd', 'start', 'end']) out += `${k}: ${meta[k] ?? 'None'}\n`;
  return `${out}type: session-transcript\n---\n\n${redact(turns.join('\n\n'))}\n`;
}

/** Session id, transcript path, or '' (latest transcript of this workspace) → markdown. Throws if not found. */
export function extract(src = '', ws = WS) {
  return render(resolve(ws, src));
}

if (isMain(import.meta.url)) {
  let src = '';
  let out = '';
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) { if (argv[i] === '-o') out = argv[++i] ?? ''; else src = argv[i]; }
  let md;
  try { md = extract(src); } catch (e) { console.error(e.message); process.exit(1); }
  if (out) fs.writeFileSync(out, md); else process.stdout.write(md);
}

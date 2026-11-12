#!/usr/bin/env node
// Open a vault file in Obsidian through the obsidian:// URI (works when there is no `obsidian` binary on PATH).
// Node twin of tools/obsidian-open.sh (same behaviour). Vault = this workspace (vault name = workspace folder name).
// Usage: node tools/obsidian-open.mjs <vault-relative path>     e.g. node tools/obsidian-open.mjs views/2026-11-08-plan.md
//        node tools/obsidian-open.mjs --print <path>            only print the URI
import fs from 'node:fs';
import path from 'node:path';
import { ws, run, slashes } from './_lib.mjs';

const args = process.argv.slice(2);
const print = args[0] === '--print';
if (print) args.shift();
let file = args[0];
if (!file) { console.error('usage: obsidian-open.mjs [--print] <vault-relative path>'); process.exit(1); }
if (process.platform === 'win32') file = slashes(file);
file = file.replace(/^\.\//, '');

// percent-encode everything except unreserved characters (UTF-8 safe)
const urlenc = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

const uri = `obsidian://open?vault=${urlenc(path.basename(ws))}&file=${urlenc(file)}`;
if (print) { console.log(uri); process.exit(0); }

const open = (cmd, a) => run(cmd, a, { quiet: true, stdio: 'ignore' }).code;
const rundll = () => open('rundll32.exe', ['url.dll,FileProtocolHandler', uri]);
let code;
if (process.platform === 'win32') code = rundll();
else if (process.platform === 'darwin') code = open('open', [uri]);
else {
  let wsl = false;
  try { wsl = /microsoft/i.test(fs.readFileSync('/proc/version', 'utf8')); } catch { /* not Linux-like */ }
  code = wsl ? rundll() : 127;                       // WSL → Obsidian on the Windows side
  if (code === 127) code = open('xdg-open', [uri]);
}
process.exit(code);

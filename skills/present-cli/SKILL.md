---
name: present-cli
description: CLI mode for present-visually — the terminal can't render mermaid, so every visual (diagrams, tables, digests) is written to a markdown file in the Obsidian vault and opened in Obsidian, while chat keeps short text-only chunks. Use when the user says "I'm in CLI", "I'm in the terminal", "in Claude Code CLI", "can't see the diagram/mermaid", "show it visually", or "open it in Obsidian".
updated: 2026-11-08
---

# Present visually — CLI mode

Extends skill `present-visually` (load it too; all its rules hold). Only the **rendering** changes.

## When to use
- User signals a terminal session (trigger phrases above). **Sticky**: stays on for the rest of the session until the user says otherwise.
- Applies to every multi-part presentation after that, not just the one that triggered it.

## Steps
1. **Pick the file** (must be inside the vault = workspace root; Obsidian can't open files outside it):
   - Task digest already exists (`work/<project>/<date>-<slug>/review.md`) → use it (regenerate if stale, per present-visually §1).
   - Ad-hoc explanation (no task dir) → `views/<YYYY-MM-DD>-<slug>.md` (gitignored, throwaway). Same slug + same day → overwrite.
2. **Write the whole thing** to that file: frontmatter (`title`, `based_on`, `based_on_updated`), then every chunk as `## <n> · <headline>` with its mermaid / tables. All chunks at once — the user scrolls in Obsidian; chat still goes chunk by chunk.
3. **Open it in Obsidian** (trigger phrase = consent to open; don't ask again this session):
   ```bash
   f=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "<vault-relative path>")
   v=$(python3 -c 'import urllib.parse,os;print(urllib.parse.quote(os.path.basename(os.getcwd()),safe=""))')
   { xdg-open "obsidian://open?vault=$v&file=$f" || open "obsidian://open?vault=$v&file=$f"; } >/dev/null 2>&1
   ```
   Already open in Obsidian → just rewrite the file; Obsidian live-reloads. Skip re-opening.
4. **Chat side, per chunk**:
   - Headline + ≤ ~7 bullets / one small table. **No raw mermaid in chat** — instead `🖼 diagram: §<n> in Obsidian`.
   - First chunk adds the file path: `🖼 opened in Obsidian: <vault-relative path>`.
   - Same chunk menu at the end; wait between chunks unless "all".
5. Plan edited later → edit precise doc first, regenerate the file (present-visually §7), say `🖼 updated in Obsidian`.

## Verify
- `xdg-open` exit 0 only means it launched — first time, ask the user to confirm the note rendered.

## Fallbacks
- Obsidian missing / user away from desktop → offer an Artifact page (private claude.ai page renders mermaid in browser).
- VS Code: `code <file>` + Ctrl+Shift+V, needs extension `bierner.markdown-mermaid`.

## Pitfalls
- Obsidian is a flatpak here (`md.obsidian.Obsidian`), no `obsidian` binary on PATH — always go through the `obsidian://` URI.
- Vault name = workspace folder name (run from the workspace root). "Vault not found" → check the vault list in Obsidian's `obsidian.json` (Linux `~/.config/obsidian/`, Flatpak `~/.var/app/md.obsidian.Obsidian/config/obsidian/`, macOS `~/Library/Application Support/obsidian/`).
- URL-encode the path (`/` → `%2F`), else nested paths fail.
- Don't put views under `projects/*/`, `.claude/`, or dot-folders — Obsidian ignores those (`.obsidian/app.json` `userIgnoreFilters`).
- `views/` is scratch, not history: lasting plans belong in `work/` task dirs, decisions in the wiki.

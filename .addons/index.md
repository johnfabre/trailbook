# Add-ons

Optional packages for this workspace. **Inert until asked**: agents never read, search, load or apply anything in `.addons/` unless the user explicitly asks to list, install, upgrade, uninstall or run an add-on (AGENTS.md hard rule). The folder is also hidden from Obsidian (dot-folder) and from default ripgrep-based searches such as Grep and Glob (`.ignore`).

Each add-on is **one self-contained markdown file**: what it does, the install steps for the agent, and every file it adds as an extractable `~~~~<lang> file=<path>` block. Installing copies those files into the live workspace (`skills/`, `agents/`, `tools/`) and wires the indexes. From then on it behaves like a built-in skill.

| add-on | file | adds | trigger once installed |
|---|---|---|---|
| repo-review | [repo-review.md](repo-review.md) | skill `repo-review`, 6 `audit-*` agents, tools `repo-inventory` + `evidence-check` | "review / audit / take over <repo>" |

## For the agent: only when the user asks
- **"list add-ons"** → show the table above. Nothing else.
- **"install <add-on>"** → open `.addons/<add-on>.md`, go to its § Install and follow it exactly, with the source file = that path (nothing to fetch).
- **"upgrade / uninstall <add-on>"** → the same file, § Upgrade / uninstall.
- **The user asks for something an add-on covers, but it isn't installed** (e.g. "review acme" with no `skills/repo-review/`) → say in one line that it's an available add-on and offer to install it (one-time install, then a new session so its agents load). Don't run it straight from `.addons/`.
- **Share**: an add-on file can be published as a gist unchanged. Another Trailbook installs it from the URL with the same § Install.

## Adding an add-on
One file `.addons/<name>.md` with sections What it does · Requirements · Install (numbered, mechanical extraction, self-test, log, announce) · Use · Upgrade / uninstall · Files. Add one row to the table above. Tools inside it follow the workspace rules (`.mjs` + `.sh` twins, no python/jq).

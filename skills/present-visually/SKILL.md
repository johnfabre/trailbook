---
name: present-visually
description: How to show information to the user with low cognitive load — chunk-by-chunk, mermaid diagrams, tables, and annotated HTML mockups — without losing precision. Also stores plans so they can be reviewed again in a later session. Use whenever presenting a plan, spec, design, review, comparison, or any multi-part explanation, and when the user asks to "review the plan for <feature> in <project>".
updated: 2026-11-08
---

# Present visually

User preference: **read chunk by chunk, see visuals, minimum cognitive load, zero loss of precision.**

## 1. Two layers — never mix them up
| Layer | File | Purpose | Rule |
|---|---|---|---|
| **Precise** | `spec.md` / `brief.md` / `plan.md` in the task dir | exact truth: files, fields, steps, decisions | source of truth; never simplified |
| **Review digest** | `review.md` in the same dir (+ `mockups/*.html`) | what the user reads | every chunk links to the precise section it summarizes; adds nothing not in the precise doc |

Digest frontmatter: `based_on: spec.md` + `based_on_updated: <updated date of that doc>`. Precise doc newer → digest stale → regenerate before showing.

## 2. Where plans live (not the wiki)
- Plans/specs are **task artifacts with a lifecycle** → `work/<project>/<YYYY-MM-DD>-<slug>/`, registered in `work/index.md`.
- Wiki = durable knowledge. Lasting decisions ("why we chose X") reach the wiki as `decision-` pages via `session-close` / `wiki-ingester`, linking back to the task dir.
- Non-dev plans (workspace changes, research plans) → project `_workspace` or the relevant project, same structure, `plan.md` as precise doc.
- A plan approved in Claude Code plan mode (`~/.claude/plans/*.md`) → copy into the task dir as `plan.md`; that copy is canonical.

## 3. Chunking (chat)
- **Chunk 1 always = overview**: 3-line TL;DR + one big-picture mermaid diagram + chunk menu.
- One topic per chunk. ≤ ~7 bullets or 1 table + 1 diagram. Headline states the point, not the topic ("3 tables change, no migrations", not "Data model").
- End every chunk with the menu: `▶ next: 2 changes · 3 flow · 4 UI · 5 risks & decisions · 6 verify — say "next", a number, or "all"`.
- Wait for the user between chunks unless they say "all".
- Open decisions / assumptions: always their own chunk, never buried. Mark `❓ decision needed` / `⚠️ assumption`.

Default plan chunks: 1 overview · 2 what changes (table) · 3 how it flows (diagram) · 4 UI (mockups, if any) · 5 risks & open decisions · 6 verification · 7 out of scope.

## 4. Pick the visual
| Content | Use |
|---|---|
| process, workflow, branching | mermaid `flowchart` |
| request/response, agents talking | mermaid `sequenceDiagram` |
| lifecycle, statuses | mermaid `stateDiagram-v2` |
| data model | mermaid `erDiagram` (show only changed + neighboring entities; mark new/changed in labels) |
| components / services | mermaid `flowchart` with subgraphs |
| timeline / phases | mermaid `gantt` or `timeline` |
| file changes, comparisons, options, decisions | table (`file · change · why`), ✅/❌/⚠️ cells |
| UI | annotated HTML mockup (§5) |
| before → after | two-column table or side-by-side diagrams |

Mermaid hygiene: ≤ ~15 nodes per diagram (split otherwise), short labels, `<br/>` for second lines, no styling noise. Wiki-style links don't work inside mermaid — reference paths as text.

## 5. HTML mockups
- Start from `skills/present-visually/refs/mockup-template.html`. One file per screen in `<task dir>/mockups/<screen>.html`; states (default/loading/empty/error) as sections in the same file.
- Self-contained: inline CSS, no external requests. Realistic copy, not lorem ipsum.
- Annotations: numbered badge on the element (`data-note="1"`) + matching entry in the side legend + `<!-- NOTE 1: … -->` in source. Toggle button hides them.
- Mark what is **new** vs **existing** vs **changed** (template classes `.is-new`, `.is-changed`).
- Show: `xdg-open <file>` (ask first) or tell the user the path; Obsidian can also open it.
- Apply `skills/a11y/SKILL.md` in the mockup itself (labels, contrast, focus order noted).

## 6. Rendering
- Chat: mermaid shows as code — keep diagrams small; say `rendered: open <task dir>/review.md in Obsidian` (Obsidian renders mermaid + tables).
- **CLI session** (user says "I'm in CLI" / can't see mermaid) → skill `present-cli`: write visuals to a vault file and open it in Obsidian; no raw mermaid in chat.
- Tables in chat: ≤ 5 columns, short cells; move long text to the precise doc and link it.

## 7. "Review the plan for X in project Y" (any session)
1. `work/index.md` → match project + feature words (title, slug, aliases). Several matches → short table, ask which.
2. Open task dir. `review.md` stale or missing → regenerate from the precise doc (§1).
3. Present chunk 1, menu, wait. Answer drill-down questions from the precise doc, citing its section.
4. User changes the plan → edit the **precise doc first**, then regenerate the affected digest chunks, bump `updated:`, log `status.md`.

## Pitfalls
- Never let the digest say something the precise doc doesn't. If summarizing drops a caveat, the caveat goes in the chunk.
- Don't decorate: no diagram for 2 facts; a sentence is fine.
- Numbers, names, paths, and field names stay exact in the digest — simplify structure, not facts.

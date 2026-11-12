---
name: wiki-ingest
description: Ingest a new source (article, doc, notes, transcript, URL) into the workspace wiki. Always runs in a wiki-ingester subagent (haiku by default, escalating to sonnet then opus). Use when the user says add/read/ingest/file this source; session-close also uses it.
updated: 2026-11-08
---

# Wiki ingest

**Hard rule: ingest always runs in a `wiki-ingester` subagent. The main agent never writes wiki pages for an ingest itself.**

## Main agent steps
1. **Store raw** (immutable after this):
   - File → copy to `wiki/raw/<kebab-name>.<ext>`. URL → fetch, convert to markdown, save there with source URL + fetch date on top. Pasted text → save as markdown.
   - Images → `wiki/raw/assets/`. Then `chmod a-w` the raw file.
   - Don't read the source in full yourself — that's the ingester's job.
2. **Pick model** (cheapest first):
   | Source | Model |
   |---|---|
   | default: articles, notes, session transcripts, docs | **haiku** |
   | long (> ~40k tokens) and dense/technical, or many expected conflicts with existing pages | sonnet |
   | only after sonnet returns `ESCALATE` | opus |
3. **Announce + spawn** (AGENTS.md rule): `🤖 spawning wiki-ingester — ingest <title> — model haiku/low`.
   Prompt: raw path, kind, hints (≤ 5 lines: what mattered to the user, project, task dirs/PRs). Paths only, no contents.
4. **Route on STATUS**:
   - `DONE` / `NOTHING_TO_FILE` → tell user one line: pages created/updated.
   - `ESCALATE` → `⬆️ escalating wiki-ingester haiku → sonnet — <reason>`, fresh spawn, same prompt + the reason. Sonnet escalates → opus.
   - `BLOCKED` → surface to user.
5. Batch of several sources → one ingester per source, parallel, each haiku.

## Ingester steps (followed by the subagent)
1. **Read** the raw source fully (only time it's read in full).
2. **Find what exists**: `wiki/index.md`; `grep -ril -E '<term1>|<term2>' wiki/ --exclude-dir=raw`; read heads (`head -20`) of matches only.
3. **Source page** `wiki/sources/src-<slug>.md` (sessions: `src-session-<YYYY-MM-DD>-<slug>`):
   frontmatter (`type: source`, `raw: raw/<file>`, `url:` if any, `ingested:`, `project:` if any) + TL;DR + key points + links to pages touched. Short — raw is always there.
4. **Decision pages** `wiki/decisions/decision-<slug>.md` for every real decision:
   ```
   ---
   title: <decision as a statement>
   type: decision
   tags: [<domain>, <project>]
   project: <name | —>
   date: YYYY-MM-DD
   status: active | superseded
   sources: [src-..]
   updated: YYYY-MM-DD
   ---
   **TL;DR:** <decision> — because <main reason>.
   ## Context
   ## Why  (reasons, constraints)
   ## Alternatives rejected  (option — why not)
   ## Links  (work/<task dir>, PR #, related [[pages]])
   ```
   A decision that replaces an older one → old page `status: superseded` + link to new.
5. **Entity/concept pages**: add facts with `(from [[src-<slug>]])`; create only if central or likely to recur; `## Related` links both ways; bump `updated:`. Conflicts → `## Conflicts` with both sides cited, never overwrite.
6. **Index**: lines in `wiki/index.md` under the right section for every page created or whose TL;DR changed.
7. **Log**: `## [date] ingest | <title>` + pages touched.
8. **Verify**: `node tools/wiki-lint.mjs` → clean (fix what you broke).

## Pitfalls
- No code in the wiki. Point to paths/PRs instead.
- TL;DRs are what most future reads see — make the "why" fit in them.

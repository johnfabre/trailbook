---
name: wiki-query
description: Answer a knowledge question from the workspace wiki using cheap tiered reads, cite pages, and file valuable answers back into wiki/notes/. Use for any "what do we know about / how does / compare" question.
updated: 2026-11-08
---

# Wiki query

## Steps

1. **T1**: read `wiki/index.md`; pick candidate pages. "Why…" questions → `## Decisions` section first (TL;DR holds the reason).
2. **Widen if needed**: `grep -ril -E '<term1>|<term2>' wiki/ --exclude-dir=raw`.
3. **T2**: `head -20` each candidate (frontmatter + TL;DR). Stop if enough.
4. **T3**: read full pages only for the ones that matter.
5. **T4**: open `wiki/raw/` only if pages lack a needed detail — then also improve the page so next time T3 suffices.
6. **Answer** with citations `[[slug]]`. Say clearly when the wiki doesn't cover something; offer to research / ingest.

## File it back
If the answer is a synthesis, comparison, or analysis that took real work:
- Save as `wiki/notes/note-<slug>.md` (`type: note`, `sources:` = pages used, TL;DR).
- Link from relevant entity/concept pages under `## Related`.
- Add index line; log `## [date] query | <question short>`.
Trivial lookups: don't file, don't log.

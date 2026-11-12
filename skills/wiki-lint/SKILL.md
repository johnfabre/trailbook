---
name: wiki-lint
description: Health-check the workspace wiki, project cards, and skills — broken links, orphans, missing index lines, stale pages, contradictions, gaps. Use when the user asks to lint/clean up/health-check the workspace, or periodically.
updated: 2026-11-08
---

# Wiki lint

## Mechanical checks (run first, cheap)

```bash
node tools/wiki-lint.mjs     # exit 0 = clean; else prints sections per problem
```
Checks: broken `[[links]]`, pages missing from `wiki/index.md`, orphans, skills/cards missing from their index, pages without frontmatter/TL;DR.
New mechanical check worth automating → add it to the script, not here.

## Judgment checks (read heads, T2)
- Contradictions between pages not yet under `## Conflicts`.
- Stale: `updated:` old while newer sources touch same topic.
- Concepts mentioned in ≥ 3 pages without own page → propose page.
- Project cards: `onboarded_commit` far behind → suggest refresh.
- Skills unused / overlapping → propose merge.
- Gaps worth a web search or new source → list as suggestions.

## Output
- Fix mechanical issues directly (add index lines, fix links).
- Report judgment items to user as a short list; fix only what they approve.
- Log `## [date] lint | <n> fixes, <m> suggestions`.

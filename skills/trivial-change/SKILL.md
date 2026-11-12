---
name: trivial-change
description: Flow for trivial changes (typo, copy text, config value, rename) in a project — main agent edits inline, a mechanical diff gate and one haiku review decide whether it stays trivial or is promoted to simple-change, then commit + PR. Loaded by dev-workflow after classification.
updated: 2026-11-09
---

# Trivial change

Why: for a one-liner, spawning developer + reviewer + QA costs far more than the change. Here the main agent edits itself;
two cheap checks catch misclassification and **promote** to `simple-change` without losing work.
Prereq: `dev-workflow` §1 (card + project skill), §4 (checkout-base + task branch) done.

```
brief(short) → main edits → trivial-gate ─PROMOTE→ simple-change (keep diff)
                                └OK→ fast check → haiku review ─CHANGES_REQUESTED→ simple-change
                                                      └APPROVED→ dev-workflow §8
```

## Eligible — all must hold (else simple-change)
- Typo, copy/text, comment, config value, rename of a local identifier, version string, doc tweak.
- ≤ 2 files, ≤ 20 changed lines (the gate checks this mechanically).
- No logic / control-flow change, no new dependency, no test changes needed.
- Intent unambiguous from the request.
- Project skill doesn't forbid main-agent edits (check its § Conflicts — **repo wins**).

## Steps
1. **Announce**: `→ trivial-change: <why>` (user may override → simple-change).
2. **Task dir** (lean): `brief.md` ≤ 10 lines (request, file(s), acceptance criterion) + `status.md`; line in `work/index.md`.
3. **Edit** inline: read only the target region, make the change.
4. **Gate** (mechanical, ~0 tokens): `node tools/trivial-gate.mjs projects/<name>` → read last 3 lines.
   `PROMOTE` → step 7. `OK` → continue.
5. **Fast check**: card's cheapest relevant command (lint / single test / format check); read only the tail. Fail → step 7.
6. **Review** — `🤖 spawning code-reviewer — check trivial diff vs brief — model haiku/low`.
   Prompt adds: "Trivial path. Also answer: is this really trivial (no behavior change)? If not → CHANGES_REQUESTED with reason `not trivial`."
   `APPROVED` → `dev-workflow` §8 (PR body notes "trivial path: gate OK, fast check OK, haiku review APPROVED").
   `CHANGES_REQUESTED` → step 7 (no inline fix rounds on this path).
7. **Promote**: `⬆️ promoting trivial → simple-change — <gate reason | check failure | review-1.md>`.
   Keep the working tree. Expand `brief.md` to the simple-change template. Continue in `simple-change`:
   with `review-1.md` → step 2 with "Address `review-1.md`, starting from the current diff"; otherwise → step 3 (review the current diff).
   Models from here: simple-change column of §5a.

Log each step in `status.md`: `HH:MM main r1 [inline] DONE` · `HH:MM gate OK (1 files, 2 lines)` · `HH:MM code-reviewer r1 [haiku/low] APPROVED`.

## Pitfalls
- Don't stretch eligibility to dodge the flow — "unsure" means simple-change.
- The gate counts untracked files too; generated files or a stray lockfile will (correctly) promote.
- `auth`-like path names (incl. e.g. `AUTHORS`) promote by design; the user can override.

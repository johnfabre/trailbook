---
name: simple-change
description: Flow for surgical changes (bug fix, small tweak, single lib, no data-model change) in a project — developer → code-reviewer → qa-tester loop, then main agent commits and opens PR. Loaded by dev-workflow after classification.
updated: 2026-11-08
---

# Simple change

Prereq: `dev-workflow` steps 1–4 done (card read, branch created, task dir exists).

```
brief → developer ⇄ code-reviewer → qa-tester ─FAIL→ developer
                                        └PASS→ main final (dev-workflow §8)
```

## Steps
1. **Brief**: write `brief.md` — request, scope (files/areas if known), acceptance criteria (testable bullets), relevant card commands. ≤ 30 lines.
2. **Developer** (`developer`): "Implement brief. Task dir: … Repo: … Card: … Round n."
   → `STATUS: DONE` (or BLOCKED).
3. **Code review** (`code-reviewer`): "Review working-tree diff vs brief. Round n."
   - `CHANGES_REQUESTED` → back to developer with "Address `review-<n>.md`." → re-review (n+1).
   - `APPROVED` → step 4.
4. **QA** (`qa-tester`): "Execute phase. Verify brief acceptance criteria; run project tests; add regression test for the fix if feasible. Round n."
   - `FAIL` → developer with "Fix failures in `qa-<n>.md`." → back to step 3 (re-review the new diff).
   - `PASS` → step 5.
5. **Finish**: `dev-workflow` §8.

Every spawn: `model` + `effort` per `dev-workflow` §5a (promoted from trivial-change → simple column). QA re-runs after a fix → haiku. Re-rounds continue the same agent.
Log each transition as one line in `status.md`: `HH:MM <role> r<n> [<model>/<effort>] <STATUS>`.
Loop limits per `dev-workflow` §6.

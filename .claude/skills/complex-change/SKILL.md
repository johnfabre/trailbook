---
name: complex-change
description: Flow for features, multi-lib, data-model, or API changes in a project — business-analyst spec iterated with main agent, user approval gate, then developer and QA test-prep in parallel, code review, QA execution, optional UX and a11y, then main agent commits and opens PR. Loaded by dev-workflow after classification.
updated: 2026-11-08
---

# Complex change

Prereq: `dev-workflow` steps 1–4 done.

```
brief → BA spec ⇄ main agent → [ux-expert mockups, if UI] → USER APPROVES SPEC (+ mockups)
   ├─ developer ⇄ code-reviewer ─APPROVED─┐
   └─ qa-tester PREP (test-plan) ⇄ BA review ─────────────────────────────┤
                                                    qa-tester EXECUTE ←───┘
                                                      ├FAIL→ developer → re-review
                                                      └PASS→ main final
```

## Steps
1. **Brief**: `brief.md` — request as user stated it, known constraints, open questions. No solution design.
2. **Spec** (`business-analyst`): "Write spec from brief. Round n."
   → `spec.md`: problem, scope / out of scope, user stories + acceptance criteria (Given/When/Then), data-model / API changes, affected libs, risks, open questions.
   Main agent reviews spec vs brief + card. Gaps → BA round n+1 with notes appended to `brief.md` under `## Main agent notes r<n>`.
3. **UX** (`ux-expert`, only if UI): "Mockups from spec." → `mockups/*.html` (annotated) + `ux.md`. Before the gate, so the user approves spec and UI together.
4. **USER GATE** — hard stop. Write `review.md` digest and present it per skill `present-visually` (chunk by chunk: overview → changes → flow → UI mockups → risks & ❓ decisions → verification). `work/index.md` status → `awaiting-approval`. Proceed only on explicit approval (→ `approved`). Changes → edit spec first (BA round), regenerate digest, re-ask.
5. **Parallel** — spawn in one message:
   - `developer`: "Implement spec.md (+ ux.md, mockups/). Round 1."
   - `qa-tester`: "PREP phase: write test-plan.md from spec. Don't run or write code tests yet."
6. **Review loops** (run independently):
   - Dev side: `code-reviewer` "Review diff vs spec.md (+ ux.md)." `CHANGES_REQUESTED` ⇄ developer.
   - QA side: `business-analyst` "Review test-plan.md coverage vs spec acceptance criteria." Changes ⇄ qa-tester prep.
   - If UI: `ux-expert` "Review implementation vs ux.md" after code-review APPROVED; issues → developer → code-review again.
7. **QA execute** (`qa-tester`), only when code review APPROVED **and** test plan approved:
   "EXECUTE phase: implement automated tests from test-plan.md, run unit/e2e, do manual/UI checks listed. Round n."
   - `FAIL` → developer "Fix failures in `qa-<n>.md`" → code review → QA execute again.
   - `PASS` → step 8.
8. **Finish**: `dev-workflow` §8. PR description links spec, test plan, final verdicts.

Every spawn: `model` + `effort` per `dev-workflow` §5a (BA spec + dev + review → opus; prep, UX, BA test-plan review → sonnet; QA re-runs → haiku). Re-rounds continue the same agent.
Log each transition in `status.md` with `[<model>/<effort>]`. Loop limits per `dev-workflow` §6.

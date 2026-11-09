---
name: a11y
description: WCAG 2.2 AA accessibility checklist and tooling for UI work — used by business-analyst, ux-expert, developer, code-reviewer, and qa-tester whenever a change touches UI. Use for "accessibility", "a11y", "WCAG", screen reader, keyboard, or contrast questions.
updated: 2026-11-08
---

# a11y — WCAG 2.2 AA

Target: WCAG 2.2 level AA. Apply only the items relevant to the change.

## Checklist
**Perceivable**
- Images: meaningful → `alt` text; decorative → `alt=""` / `aria-hidden`. Icons-only controls have accessible names. (1.1.1)
- Semantics: real headings in order, lists, tables with headers, landmarks (`main`, `nav`, …). (1.3.1)
- Form inputs have programmatic labels; required/format stated in text, not color alone. (1.3.1, 1.4.1, 3.3.2)
- Contrast: text 4.5:1, large text 3:1, UI components/focus indicators/graphics 3:1. (1.4.3, 1.4.11)
- Reflow at 320 CSS px with no 2-D scroll; text resizable to 200%; text spacing overrides don't break layout. (1.4.4, 1.4.10, 1.4.12)
- Hover/focus content dismissible, hoverable, persistent. (1.4.13)

**Operable**
- Everything works by keyboard; no traps; logical focus order. (2.1.1, 2.1.2, 2.4.3)
- Focus visible **and not obscured** by sticky headers/overlays. (2.4.7, 2.4.11 — new in 2.2)
- Pointer targets ≥ 24×24 CSS px or enough spacing. (2.5.8 — new)
- Dragging actions have a single-pointer alternative. (2.5.7 — new)
- Visible label text is contained in accessible name. (2.5.3)
- Skip link / bypass blocks; descriptive page titles, link text. (2.4.1, 2.4.2, 2.4.4)
- No timing without control; motion/animation respects `prefers-reduced-motion`. (2.2.1, 2.3.3 best practice)

**Understandable**
- `lang` set; no unexpected context change on focus/input. (3.1.1, 3.2.1, 3.2.2)
- Errors identified in text, with suggestions; important submissions reversible/confirmable. (3.3.1, 3.3.3, 3.3.4)
- Help mechanisms in consistent place. (3.2.6 — new)
- Don't make users re-enter info already given in the same flow. (3.3.7 — new)
- Auth without cognitive tests (allow paste, password managers). (3.3.8 — new)

**Robust**
- Valid name/role/value for custom widgets; prefer native elements over ARIA; ARIA patterns per APG. (4.1.2)
- Status messages announced via `role="status"` / `aria-live` without moving focus. (4.1.3)

## Tooling (use what the project has; don't add deps unasked)
- Lint: `eslint-plugin-jsx-a11y`, `eslint-plugin-vuejs-accessibility`, `@angular-eslint` template a11y rules.
- Automated: `@axe-core/playwright` / `cypress-axe` / `jest-axe` in tests; `npx @axe-core/cli <url>`; Lighthouse a11y audit.
- Automated tools catch ~30–40%: always also do a keyboard-only pass and check names with a screen reader or the accessibility tree.

## Reporting
Findings as `- [blocker|major|minor] <where> — <criterion #> <issue> → <fix>`. Blocker = keyboard trap, missing name on control, contrast failure on primary content, inaccessible auth.

# Execution: Add ANSI Color Parsing to Logs Table Plugin

> Results are annotated inline: `-- **value**` for discovered values, `-- **passes/FAILED**` for verification.

## Phase 1: Add Dependencies and Create ANSI Utility

Depends on: nothing
Parallel with: Phase 2 (no file overlap)
Type: implementation
Projects: perses-plugins/logstable

- [x] Add `ansi_up` and `dompurify` as dependencies - `logstable/package.json` -- **done**
- [x] Create ANSI-to-HTML conversion utility with sanitization - `logstable/src/utils/ansi.ts` -- **done**
  - `ansiToSanitizedHtml()` — converts ANSI string to sanitized HTML, returns `null` for plain text
  - `stripAnsi()` — removes ANSI escape sequences for clipboard
- [x] Additional: updated `logstable/jest.config.ts` to transform ESM-only `ansi_up` package -- **needed for Jest**
- [x] Note: used `{ AnsiUp }` named import (not default) — `ansi_up` v6 is ESM with named export

### Phase 1 Verification

- [x] `npm install` in `logstable/` resolves without errors -- **passes**
- [x] `npx tsc --noEmit` passes with the new utility file -- **passes**
- [x] `npm test` — 30 tests pass (25 existing + 5 new) -- **passes**

---

## Phase 2: Add Theme-Aware ANSI Color Styles via CSS

Depends on: nothing
Parallel with: Phase 1 (no file overlap)
Type: configuration
Projects: perses-plugins/logstable

- [x] Create CSS file with ANSI color classes using CSS custom properties - `logstable/src/components/LogRow/ansiColors.css` -- **done**
  - Light mode defaults on `:root`
  - Dark mode overrides via `[data-mui-color-scheme="dark"]`, `.dark-mode`, and `@media (prefers-color-scheme: dark)`
  - Foreground, background, and bold classes mapping to custom properties
- [ ] Import CSS file in LogRow.tsx - deferred to Phase 3 (same file modified there)

### Phase 2 Verification

- [x] CSS file created with correct syntax -- **done**

---
## Phases 1 and 2 can run in parallel (no file overlap)
---

## Phase 3: Integrate ANSI Rendering into LogRow

Depends on: Phase 1, Phase 2
Parallel with: none
Type: implementation
Projects: perses-plugins/logstable

### 3a. ANSI rendering in LogRow component

- [x] Write failing tests for ANSI colored log rendering - `logstable/src/components/LogRow/LogRow.test.tsx` -- **2 tests added**
- [x] Implement ANSI rendering with conditional `dangerouslySetInnerHTML` - `logstable/src/components/LogRow/LogRow.tsx` -- **done**
  - Added `useMemo` for `ansiToSanitizedHtml(log.line)` call
  - Conditional render: `dangerouslySetInnerHTML` for ANSI lines, plain text children otherwise
  - Imported `ansiColors.css` and `ansiToSanitizedHtml`

### 3b. ANSI stripping in copy helpers

- [x] Write failing tests for ANSI stripping in copy operations - `logstable/src/utils/copyHelpers.test.ts` -- **3 tests added**
- [x] Update `formatLogMessage` and `formatLogEntry` to strip ANSI codes - `logstable/src/utils/copyHelpers.ts` -- **done**
  - `formatLogAsJson` intentionally unchanged (preserves raw data)

### Phase 3 Verification

- [x] `npx tsc --noEmit` passes -- **passes**
- [x] `npm test` in `logstable/` — 35 tests pass (all existing + 5 new) -- **passes**

---

## Phase 4: Testing

Depends on: Phase 3
Parallel with: none
Type: implementation
Projects: perses-plugins/logstable

- [x] Write comprehensive unit tests for ANSI utility - `logstable/src/utils/ansi.test.ts` -- **13 new tests added (18 total)**
  - Multiple colors on one line
  - Bright color codes
  - 256-color codes (inline style fallback)
  - Background colors
  - Bold text (note: ansi_up uses inline style, not CSS class for bold)
  - Mixed ANSI and plain text
  - XSS via event handlers (onerror) — stripped by ansi_up HTML escaping + DOMPurify
  - XSS via javascript: href — stripped
  - Empty string → returns null
  - Lone reset code — handles gracefully
  - stripAnsi with multiple codes (bold + color)
  - stripAnsi with 256-color codes
  - stripAnsi preserves non-ANSI special chars

### Phase 4 Verification

- [x] `npm test` in `logstable/` — 48 tests pass across 4 suites -- **passes**
- [x] `npx tsc --noEmit` passes -- **passes**
- [x] XSS prevention tests specifically pass -- **passes (double-layered: ansi_up escapes HTML + DOMPurify strips)**

---

## Summary

**Status:** Complete (4 of 4 phases done)

### Files changed

| File | Change |
| ---- | ------ |
| `logstable/package.json` | Added `ansi_up: ^6.0.0` and `dompurify: ^3.2.3` as dependencies |
| `logstable/jest.config.ts` | Added `ansi_up` to `transformIgnorePatterns` (ESM-only package) |
| `logstable/src/utils/ansi.ts` | **New.** `ansiToSanitizedHtml()` and `stripAnsi()` utility functions |
| `logstable/src/utils/ansi.test.ts` | **New.** 18 unit tests covering colors, edge cases, and XSS prevention |
| `logstable/src/components/LogRow/ansiColors.css` | **New.** CSS custom properties for ANSI colors with light/dark mode support |
| `logstable/src/components/LogRow/LogRow.tsx` | ANSI rendering with conditional `dangerouslySetInnerHTML`, CSS import |
| `logstable/src/components/LogRow/LogRow.test.tsx` | 2 new tests for ANSI rendering in component |
| `logstable/src/utils/copyHelpers.ts` | `formatLogMessage` and `formatLogEntry` now strip ANSI codes |
| `logstable/src/utils/copyHelpers.test.ts` | 3 new tests for ANSI stripping in copy operations |

### Notes

- `ansi_up` v6 uses named export (`{ AnsiUp }`) not default — deviated from plan which used default import
- `ansi_up` renders bold as inline `style="font-weight:bold"` not CSS class — `.ansi-bold` in CSS file won't be applied for bold. Bold still works via inline style.
- XSS protection is double-layered: `ansi_up` HTML-escapes `<` and `>` before DOMPurify runs

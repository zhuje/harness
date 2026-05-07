# Execution: Add Variable Plugins to the Loki Perses Plugin

> Results are annotated inline: `-- **value**` for discovered values, `-- **passes/FAILED**` for verification.

---
## Phases 1 and 2 ran in parallel (no file overlap)
---

## Phase 1: Update Loki Client to Support Matchers

Depends on: nothing
Parallel with: Phase 2 (CUE schemas — different files)
Type: implementation
Projects: perses-plugins

- [x] Add optional `query` parameter to `LokiClient` interface for `labels()` and `labelValues()` - `loki/src/model/loki-client.ts`
- [x] Update `labels()` function implementation to accept and pass `query` param to Loki API - `loki/src/model/loki-client.ts`
- [x] Update `labelValues()` function implementation to accept and pass `query` param to Loki API - `loki/src/model/loki-client.ts`
- [x] Add `getLokiTimeRange()` helper function - `loki/src/model/loki-client.ts`
- [x] Update `createClient` in LokiDatasource to pass through `query` parameter - `loki/src/datasources/loki-datasource/LokiDatasource.tsx`
- [x] Update any existing callers (`complete.ts`) if needed - `loki/src/components/complete.ts` -- **not needed, existing callers pass fewer args and remain valid**

### Phase 1 Verification

- [x] `cd projects/perses-plugins/loki && npm run type-check` -- **passes**
- [x] `cd projects/perses-plugins/loki && npm test` -- **passes (66 tests, 4 suites)**

### Phase 1 Notes

- 13 new tests written in `loki/src/model/loki-client.test.ts` covering `toUnixSeconds`, `getLokiTimeRange`, `labels`, and `labelValues`
- Fixed Jest 30 config issue in `jest.config.ts` and `jest.shared.ts` for ESM compatibility (pre-existing issue)

## Phase 2: Create CUE Schemas for Loki Variable Types

Depends on: nothing
Parallel with: Phase 1 (different file tree)
Type: configuration
Projects: perses-plugins

- [x] Create LokiLabelValuesVariable CUE schema - `loki/schemas/variables/loki-label-values/loki-label-values.cue`
- [x] Create LokiLabelValuesVariable valid test fixture - `loki/schemas/variables/loki-label-values/tests/valid/loki-label-values.json`
- [x] Create LokiLabelNamesVariable CUE schema - `loki/schemas/variables/loki-label-names/loki-label-names.cue`
- [x] Create LokiLabelNamesVariable valid test fixture - `loki/schemas/variables/loki-label-names/tests/valid/loki-label-names.json`
- [x] Create LokiLogQLVariable CUE schema - `loki/schemas/variables/loki-logql/loki-logql.cue`
- [x] Create LokiLogQLVariable valid test fixture - `loki/schemas/variables/loki-logql/tests/valid/loki-logql.json`
- [x] Create LokiLogQLVariable invalid test fixture - `loki/schemas/variables/loki-logql/tests/invalid/no-label.json`

### Phase 2 Verification

- [x] Schema directory structure matches the Prometheus pattern -- **matches (7 files)**
- [x] CUE files have correct `kind`, `spec`, and datasource selector references -- **correct, uses `ds "github.com/perses/plugins/loki/schemas/datasources:model"`**

## Phase 3: Implement Variable Plugin Types, Runtime Logic, and Editor UI

Depends on: Phase 1
Parallel with: none
Type: implementation
Projects: perses-plugins

### 3a. Variable types and shared helpers

- [x] Create variable options type definitions - `loki/src/variables/types.ts`
- [x] Create shared helpers and editor components - `loki/src/variables/loki-variables.tsx`
- [x] Create MatcherEditor component for stream selectors - `loki/src/variables/MatcherEditor.tsx`

### 3b. Variable plugin definitions

- [x] Implement LokiLabelValuesVariable plugin - `loki/src/variables/LokiLabelValuesVariable.tsx`
- [x] Implement LokiLabelNamesVariable plugin - `loki/src/variables/LokiLabelNamesVariable.tsx`
- [x] Implement LokiLogQLVariable plugin - `loki/src/variables/LokiLogQLVariable.tsx`

### 3c. Registration and exports

- [x] Create barrel export for variables - `loki/src/variables/index.ts`
- [x] Add variables export to main index - `loki/src/index.ts`
- [x] Register three Variable plugins in package.json - `loki/package.json`

### Phase 3 Verification

- [x] `cd projects/perses-plugins/loki && npm run type-check` -- **passes**
- [x] `cd projects/perses-plugins/loki && npm test` -- **passes (85 tests, 5 suites)**
- [x] `cd projects/perses-plugins/loki && npm run build` -- **succeeds (42 files compiled)**
- [x] All three variable plugins are exported from the module -- **confirmed**

### Phase 3 Notes

- 19 new tests in `loki/src/variables/loki-variables.test.ts` covering helpers and dependsOn logic
- LogQL editor uses `CompletionConfig { client }` (Loki pattern) instead of `{ remote: { url } }` (Prometheus pattern)
- Matchers handling: passes first matcher as `query` parameter to Loki API (Loki uses single `query` string vs Prometheus `match[]` array)

## Final Verification

- [x] **LokiLabelValuesVariable plugin exists** — exported, registered, has CUE schema, editor, and runtime
- [x] **LokiLabelNamesVariable plugin exists** — exported, registered, has CUE schema, editor, and runtime
- [x] **LokiLogQLVariable plugin exists** — exported, registered, has CUE schema, editor, and runtime
- [x] **Type check passes** — `npm run type-check` -- **passes**
- [x] **Tests pass** — `npm test` -- **85 tests pass**
- [x] **Build succeeds** — `npm run build` -- **succeeds**
- [x] **Matchers supported** — LabelValues and LabelNames accept optional matchers
- [x] **Variable dependencies tracked** — all three plugins implement `dependsOn`

---

## Summary

**Status:** Complete (3 of 3 phases done)

### Outstanding items

- [ ] Commit changes on `feat/loki-variable-plugins` branch
- [ ] Push branch and create PR to `perses/plugins` `main`

### Notes

- Jest 30 ESM config issue was fixed as a side effect (pre-existing bug in `jest.shared.ts` and `loki/jest.config.ts`)
- Loki `CompletionConfig` differs from Prometheus — LogQL editor passes `client` directly rather than a remote URL
- Matchers implementation uses first matcher as `query` parameter (Loki API limitation: single stream selector vs Prometheus array)
- `package-lock.json` was modified (likely from build/install)

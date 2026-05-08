# Execution: Refactor Alert TypeScript Interfaces to be Provider-Agnostic

> Results are annotated inline: `-- **value**` for discovered values, `-- **passes/FAILED**` for verification.

---
## Phases 1 and 2 can run in parallel (different files in same repo)
---

## Phase 1: Refactor `alerts-data.ts` to generic alert model

Depends on: nothing
Parallel with: Phase 2 (different file)
Type: implementation
Projects: perses-spec

- [x] Replace `AlertStatus`, `Receiver`, and AM-coupled `Alert` interfaces with generic `AlertState` type, `Alert`, `SuppressionRule`, `AlertsData`, and `AlertsMetadata` interfaces - `ts/src/dashboard/query-type/alerts-data.ts` -- **done**

### Phase 1 Verification

- [x] TypeScript compilation passes: `cd ts && npx tsc --noEmit` -- **passes**
- [x] No references to `AlertStatus`, `Receiver` interface types remain in `alerts-data.ts` -- **passes**
- [x] `AlertsData` interface still wraps `Alert[]` with optional metadata -- **passes**
- [x] `QueryType['AlertsQuery']` still resolves to `AlertsData` -- **passes**

## Phase 2: Refactor `silences-data.ts` to generic silence model

Depends on: nothing
Parallel with: Phase 1 (different file)
Type: implementation
Projects: perses-spec

- [x] Replace `Matcher`, `SilenceStatus`, and AM-coupled `Silence` interfaces with generic `SilenceState` type, `SilenceMatcher`, `Silence`, `SilencesData`, and `SilencesMetadata` interfaces - `ts/src/dashboard/query-type/silences-data.ts` -- **done**

### Phase 2 Verification

- [x] TypeScript compilation passes: `cd ts && npx tsc --noEmit` -- **passes**
- [x] No references to `Matcher` (standalone), `SilenceStatus` types remain in `silences-data.ts` -- **passes**
- [x] `SilencesData` interface still wraps `Silence[]` with optional metadata -- **passes**
- [x] `QueryType['SilencesQuery']` still resolves to `SilencesData` -- **passes**

## Phase 3: Verify query type mapping and exports

Depends on: Phase 1, Phase 2
Parallel with: none
Type: configuration
Projects: perses-spec

- [x] Verify `query.ts` imports `AlertsData` and `SilencesData` without changes needed - `ts/src/dashboard/query-type/query.ts` -- **passes, no changes needed**
- [x] Verify `index.ts` re-exports `'./alerts-data'` and `'./silences-data'` without changes needed - `ts/src/dashboard/query-type/index.ts` -- **passes, no changes needed**

### Phase 3 Verification

- [x] `cd ts && npx tsc --noEmit` passes with no errors -- **passes**
- [x] `cd ts && npm test` passes (if tests exist) -- **no TS tests exist in project, N/A**
- [x] Spot-check: `Alert` type has `id`, `name`, `state` fields and no `receivers` typed as `Receiver[]`, no `fingerprint` -- **passes**

---

## Summary

**Status:** Complete (3 of 3 phases done)

### Files changed

- `ts/src/dashboard/query-type/alerts-data.ts` — replaced AM-coupled types with generic `AlertState`, `Alert`, `SuppressionRule`
- `ts/src/dashboard/query-type/silences-data.ts` — replaced AM-coupled types with generic `SilenceState`, `SilenceMatcher`, `Silence`

### Outstanding items

- [ ] Commit changes on `feat/generic-alert-types` branch
- [ ] Push and create PR against `pr-21` branch

### Notes

- No TS tests exist in perses-spec; verification was via `tsc --noEmit` only
- `query.ts` and `index.ts` required zero changes — type names (`AlertsData`, `SilencesData`) and file names were preserved
- `npm install` was needed in `ts/` to resolve TypeScript compiler

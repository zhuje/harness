# Execution: Add Alert Manager Datasource Plugin to Perses

> Results are annotated inline: `-- **value**` for discovered values, `-- **passes/FAILED**` for verification.

## Phase 1: Define Alert Manager Query Types in perses-spec

Depends on: nothing
Parallel with: none
Type: implementation
Projects: perses-spec

### 1a. Go types

- [x] Create `AlertStatus`, `Receiver`, `Alert`, `AlertsData` Go types - `perses-spec/go/dashboard/alerts.go`
- [x] Create `MatchType`, `Matcher`, `SilenceStatus`, `Silence`, `SilencesData` Go types - `perses-spec/go/dashboard/alerts.go`
- [x] Run `make cue-gen` to generate CUE definitions -- **generated `cue/dashboard/alerts_go_gen.cue`**

### 1b. TypeScript types

- [x] Create `AlertStatus`, `Receiver`, `Alert`, `AlertsData` TS interfaces - `perses-spec/ts/src/dashboard/query-type/alerts-data.ts`
- [x] Create `Matcher`, `SilenceStatus`, `Silence`, `SilencesData` TS interfaces - `perses-spec/ts/src/dashboard/query-type/silences-data.ts`
- [x] Create `AlertsQueryDefinition`, `SilencesQueryDefinition` type aliases - `perses-spec/ts/src/dashboard/query-type/alerts-queries.ts`
- [x] Add `AlertsQuery` and `SilencesQuery` to `QueryType` interface - `perses-spec/ts/src/dashboard/query-type/query.ts`
- [x] Export new types from query-type barrel - `perses-spec/ts/src/dashboard/query-type/index.ts`
- [x] Export from dashboard barrel - `perses-spec/ts/src/dashboard/index.ts` -- **already re-exports via query-type**
- [x] Export from package root - `perses-spec/ts/src/index.ts` -- **already re-exports via dashboard**

### Phase 1 Verification

- [x] `cd projects/perses-spec && go build ./...` -- **passes**
- [x] `cd projects/perses-spec && make cue-gen` -- **succeeds**
- [x] `cd projects/perses-spec/ts && npm run build` -- **succeeds**
- [x] `cd projects/perses-spec/ts && npm run type-check` -- **passes**
- [x] Confirm `AlertsData` and `SilencesData` are exported from the package -- **confirmed via export chain**

> Note: Also fixed `isValidQueryPluginType` which was missing `LogQuery` from its validation array.

---

## Phase 2: Add Plugin System Support and HierarchicalTable to perses-shared

Depends on: Phase 1
Parallel with: none
Type: implementation
Projects: perses-shared

### 2a. AlertsQuery and SilencesQuery Plugin Types

- [x] Write failing tests for AlertsQueryPlugin type integration
- [x] Create `AlertsQueryPlugin` interface - `perses-shared/plugin-system/src/model/alerts-queries.ts`
- [x] Create `SilencesQueryPlugin` interface - `perses-shared/plugin-system/src/model/silences-queries.ts`
- [x] Add `AlertsQuery` and `SilencesQuery` to `SupportedPlugins` - `perses-shared/plugin-system/src/model/plugins.ts`
- [x] Export new types from model barrel - `perses-shared/plugin-system/src/model/index.ts`
- [x] Update `DataQueriesProvider` to handle new query kinds - `perses-shared/plugin-system/src/runtime/DataQueriesProvider/`
- [x] Create `useAlertsQueries` runtime hook - `perses-shared/plugin-system/src/runtime/alerts-queries.ts`
- [x] Create `useSilencesQueries` runtime hook - `perses-shared/plugin-system/src/runtime/silences-queries.ts`

### 2b. HierarchicalTable Component

- [x] Write failing tests for `useGrouping` hook (8 tests)
- [x] Create `HierarchicalTable` component - `perses-shared/components/src/HierarchicalTable/HierarchicalTable.tsx`
- [x] Create props model - `perses-shared/components/src/HierarchicalTable/model/hierarchical-table-model.ts`
- [x] Create `HierarchicalTableToolbar` - `perses-shared/components/src/HierarchicalTable/HierarchicalTableToolbar.tsx`
- [x] Create `useGrouping` hook - `perses-shared/components/src/HierarchicalTable/hooks/useGrouping.ts`
- [x] Create barrel exports - `perses-shared/components/src/HierarchicalTable/index.ts`
- [x] Export from components root - `perses-shared/components/src/index.ts`
- [x] Write component render tests (8 toolbar + 4 table tests)

### Phase 2 Verification

- [x] `cd projects/perses-shared && npm run build` -- **succeeds (15 tasks)**
- [x] `cd projects/perses-shared && npm run test` -- **passes (all suites)**
- [x] `cd projects/perses-shared && npm run lint` -- **passes**
- [x] `AlertsQueryPlugin` and `SilencesQueryPlugin` are exported from `@perses-dev/plugin-system` -- **confirmed**
- [x] `HierarchicalTable` is exported from `@perses-dev/components` -- **confirmed**

> Note: AlertsData/SilencesData types were defined locally in plugin-system model files since @perses-dev/spec hasn't been published with the new types yet. These should be migrated to import from @perses-dev/spec after Phase 1's branch is merged and published.

---

## Phase 3: Create Alert Manager Plugin Module in perses-plugins

Depends on: Phase 2
Parallel with: none
Type: implementation
Projects: perses-plugins

### 3a. Plugin scaffolding and configuration

- [x] Create `package.json` with `perses.plugins` array (7 plugins) - `perses-plugins/alert-manager/package.json`
- [x] Create `rsbuild.config.ts` with module federation (port 3015) - `perses-plugins/alert-manager/rsbuild.config.ts`
- [x] Create `tsconfig.json` - `perses-plugins/alert-manager/tsconfig.json`
- [x] Create barrel export - `perses-plugins/alert-manager/src/index.ts`
- [x] Create dev server bootstrap - `perses-plugins/alert-manager/src/bootstrap.tsx`
- [x] Create plugin module metadata - `perses-plugins/alert-manager/src/getPluginModule.ts`

### 3b. Alert Manager API client

- [x] Write failing tests for API client (11 tests) - `perses-plugins/alert-manager/src/model/alertmanager-client.test.ts`
- [x] Create API response types - `perses-plugins/alert-manager/src/model/api-types.ts`
- [x] Implement API client - `perses-plugins/alert-manager/src/model/alertmanager-client.ts`
- [x] Run tests -- **GREEN (11 pass)**

### 3c. Datasource plugin

- [x] Create plugin spec types - `perses-plugins/alert-manager/src/plugins/types.ts`
- [x] Implement datasource plugin - `perses-plugins/alert-manager/src/plugins/alertmanager-datasource.tsx`
- [x] Implement datasource editor - `perses-plugins/alert-manager/src/plugins/AlertManagerDatasourceEditor.tsx`

### 3d. Alerts query plugin

- [x] Write failing tests for get-alerts-data (4 tests)
- [x] Implement `getAlertsData` - `perses-plugins/alert-manager/src/plugins/alertmanager-alerts-query/get-alerts-data.ts`
- [x] Implement `AlertManagerAlertsQuery` plugin - `perses-plugins/alert-manager/src/plugins/alertmanager-alerts-query/AlertManagerAlertsQuery.ts`
- [x] Implement query editor - `perses-plugins/alert-manager/src/plugins/alertmanager-alerts-query/AlertManagerAlertsQueryEditor.tsx`
- [x] Run tests -- **GREEN (4 pass)**

### 3e. Silences query plugin

- [x] Write failing tests for get-silences-data (4 tests)
- [x] Implement `getSilencesData` - `perses-plugins/alert-manager/src/plugins/alertmanager-silences-query/get-silences-data.ts`
- [x] Implement `AlertManagerSilencesQuery` plugin - `perses-plugins/alert-manager/src/plugins/alertmanager-silences-query/AlertManagerSilencesQuery.ts`
- [x] Implement query editor - `perses-plugins/alert-manager/src/plugins/alertmanager-silences-query/AlertManagerSilencesQueryEditor.tsx`
- [x] Run tests -- **GREEN (4 pass)**

### 3f. Alert table panel

- [x] Write failing tests for alert-table-model (10 tests: dedup by fingerprint, dedup by labels, extractLabelKeys, getGroupKey, getGroupSummary)
- [x] Create alert table model - `perses-plugins/alert-manager/src/plugins/alert-table/alert-table-model.ts`
- [x] Implement `AlertTablePanel` component - `perses-plugins/alert-manager/src/plugins/alert-table/AlertTablePanel.tsx`
- [x] Implement `AlertTable` plugin definition - `perses-plugins/alert-manager/src/plugins/alert-table/AlertTable.ts`
- [x] Run tests -- **GREEN (10 pass)**

### 3g. Silence table panel

- [x] Write failing tests for silence-table-model (6 tests: group by status, group by createdBy, duration formatting)
- [x] Create silence table model - `perses-plugins/alert-manager/src/plugins/silence-table/silence-table-model.ts`
- [x] Implement `SilenceTablePanel` component - `perses-plugins/alert-manager/src/plugins/silence-table/SilenceTablePanel.tsx`
- [x] Implement `SilenceTable` plugin definition - `perses-plugins/alert-manager/src/plugins/silence-table/SilenceTable.ts`
- [x] Run tests -- **GREEN (6 pass)**

### 3h. Shared components

- [x] Write failing tests for StatusBadge (8 tests) and MatchersList (6 tests)
- [x] Create `StatusBadge` component - `perses-plugins/alert-manager/src/components/StatusBadge.tsx`
- [x] Create `MatchersList` component - `perses-plugins/alert-manager/src/components/MatchersList.tsx`
- [x] Create `MatcherEditor` component - `perses-plugins/alert-manager/src/components/MatcherEditor.tsx`
- [x] Run tests -- **GREEN (14 pass)**

### 3i. Explore plugins

- [x] Implement `SilenceForm` - `perses-plugins/alert-manager/src/explore/components/SilenceForm.tsx`
- [x] Implement `AlertManagerAlertsExplorer` - `perses-plugins/alert-manager/src/explore/AlertManagerAlertsExplorer.tsx`
- [x] Implement `AlertManagerSilencesExplorer` - `perses-plugins/alert-manager/src/explore/AlertManagerSilencesExplorer.tsx`

### 3j. CUE schemas

- [x] Create datasource schema - `perses-plugins/alert-manager/schemas/datasource/alertmanager.cue` -- **validated with cue vet**
- [x] Create alerts query schema - `perses-plugins/alert-manager/schemas/alertmanager-alerts-query/alertmanager-alerts-query.cue` -- **validated**
- [x] Create silences query schema - `perses-plugins/alert-manager/schemas/alertmanager-silences-query/alertmanager-silences-query.cue` -- **validated**

### Phase 3 Verification

- [x] `cd projects/perses-plugins/alert-manager && npx tsc --noEmit` -- **passes**
- [x] `cd projects/perses-plugins/alert-manager && npx jest --no-coverage` -- **7 suites, 50 tests, all pass**
- [x] All 7 module federation entry points reference files that exist -- **verified**

> Notes:
> - AlertsQueryPlugin/SilencesQueryPlugin interfaces not yet available from published @perses-dev/plugin-system — query plugins use local types with TODO
> - SilenceForm.onSubmit currently logs to console — needs wiring to AlertManagerClient at runtime
> - Icons use mdi-material-ui (project convention) instead of @mui/icons-material

---

## Phase 4: Register Alert Manager Plugin in Perses

Depends on: Phase 3
Parallel with: none
Type: configuration
Projects: perses

- [x] Add `AlertManager` entry with version `0.1.0` to plugin registry - `perses/scripts/plugin/plugin.yaml` -- **added alphabetically as first entry**

### Phase 4 Verification

- [x] `plugin.yaml` contains AlertManager entry -- **confirmed**
- [ ] Perses backend starts without errors -- [HUMAN]
- [ ] `GET /api/v1/plugins` includes `AlertManager` module -- [HUMAN]

---

## Summary

**Status:** Complete (all 4 phases done, 2 human verification items outstanding)

### Git state per project

| Project | Branch | Commits | Base |
| ------- | ------ | ------- | ---- |
| perses-spec | `feat/alertmanager-query-types` | 1 | main |
| perses-shared | `feat/alertmanager-plugin-types` | 4 | main |
| perses-plugins | `feat/alert-manager-plugin` | 2 | main |
| perses | `feat/alert-manager-plugin` | 1 | main |

### Test summary

| Project | Suites | Tests | Status |
| ------- | ------ | ----- | ------ |
| perses-spec (Go) | 1 | 3 | PASS |
| perses-spec (TS) | - | type-check only | PASS |
| perses-shared | 8 | 19 | PASS |
| perses-plugins/alert-manager | 7 | 50 | PASS |
| **Total** | **16** | **72** | **ALL PASS** |

### Outstanding items

- [ ] Perses backend starts without errors (human verification)
- [ ] `GET /api/v1/plugins` includes `AlertManager` module (human verification)
- [ ] Push branches and create PRs in dependency order: perses-spec → perses-shared → perses-plugins → perses
- [ ] After perses-spec is merged and published, migrate local type definitions in perses-shared and perses-plugins to import from `@perses-dev/spec`
- [ ] Wire SilenceForm.onSubmit to AlertManagerClient at runtime (currently logs to console)

### Notes

- Phase 1 → Phase 2 → Phase 3 → Phase 4 executed strictly sequentially due to type dependencies
- Local linking (`npm link`) resolved cross-repo deps during development; `link-with-perses.sh` had peer dependency conflicts with version mismatches (0.53.1 vs 0.54.0-beta.1)
- Fixed pre-existing bug: `isValidQueryPluginType` in perses-spec was missing `LogQuery` from validation array
- Fixed Jest 30 ESM compatibility issues in perses-shared (`__dirname` → `import.meta.url`, added `.ts` extensions to imports)
- Icons in perses-plugins use `mdi-material-ui` (project convention) instead of `@mui/icons-material`
- PRs should be created after all branches are verified end-to-end

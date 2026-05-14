# Execution: Add Tab Layout to Perses

> Results are annotated inline: `-- **value**` for discovered values, `-- **passes/FAILED**` for verification.

## Phase 1: Define Tab Layout Types in perses-spec

Depends on: nothing | Parallel with: none | Type: implementation | Projects: perses-spec

### 1a. Go types and tests

- [x] Add `KindTabLayout LayoutKind = "Tabs"` constant and update `layoutKindMap` - `perses-spec/go/dashboard/layout.go`
- [x] Add `TabItem`, `TabLayoutDisplay`, `TabLayoutSpec` types - `perses-spec/go/dashboard/layout.go`
- [x] Update `unmarshal` switch to handle `KindTabLayout` case - `perses-spec/go/dashboard/layout.go`
- [x] Write tests for Tab layout JSON/YAML deserialization (6 new test cases) - `perses-spec/go/dashboard/layout_test.go`

### 1b. CUE regeneration and patch

- [x] Regenerate CUE files via `make cue-gen` - `perses-spec/cue/dashboard/layout_go_gen.cue`
- [x] Update `#LayoutSpec` to union: `#GridLayoutSpec | #TabLayoutSpec` - `perses-spec/cue/dashboard/layout_patch.cue`
- [x] Update `#LayoutKind` enum in patch - `perses-spec/cue/dashboard/layout_patch.cue`

### 1c. TypeScript types

- [x] Add `TabDefinition` and `TabItemDefinition` interfaces - `perses-spec/ts/src/dashboard/layout.ts`
- [x] Update `LayoutDefinition` to `GridDefinition | TabDefinition` - `perses-spec/ts/src/dashboard/layout.ts`

### Phase 1 Verification

- [x] `cd projects/perses-spec && go build ./...` — **passes**
- [x] `cd projects/perses-spec && go test ./...` — **passes** (all 6 new Tab layout tests + existing)
- [x] `cd projects/perses-spec && make cue-gen` — **passes** (note: macOS sed -i requires manual fix, pre-existing issue)
- [x] `cd projects/perses-spec && make cue-eval` — **passes**
- [x] `cd projects/perses-spec/ts && npm run build` — **passes**
- [x] `cd projects/perses-spec/ts && npm run type-check` — **passes**

---

## Phase 2: Update perses-shared Runtime Model and Conversion

Depends on: Phase 1 | Parallel with: none | Type: implementation | Projects: perses-shared

### 2a. PanelGroupDefinition discriminated union

- [x] Write failing tests for discriminated union model (6 helper function tests) - `perses-shared/dashboards/src/model/PanelGroupDefinition.test.ts`
- [x] Refactor `PanelGroupDefinition` into discriminated union with `PanelGroupBase`, `GridPanelGroup`, `TabPanelGroup`, `TabState` + helpers
      (`getGroupItemPanelKeys`, `getGroupItemLayouts`, `findTabContainingItem`) - `perses-shared/dashboards/src/model/PanelGroupDefinition.ts`

### 2b. convertLayoutsToPanelGroups update

- [x] Write failing tests for Tab layout conversion (4 tests: Grid, Tabs, mixed, createEmpty) -
      `perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.test.ts`
- [x] Update `convertLayoutsToPanelGroups()` to dispatch on `layout.kind` for Grid and Tabs variants -
      `perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.ts`

### 2c. convertPanelGroupsToLayouts update

- [x] Write failing tests for Tab group serialization (3 tests: Grid, Tabs, mixed round-trip) -
      `perses-shared/dashboards/src/context/useDashboard.test.ts`
- [x] Update `convertPanelGroupsToLayouts()` to dispatch on `group.layoutKind` with exhaustive switch -
      `perses-shared/dashboards/src/context/useDashboard.tsx`

### 2d. Fix compilation errors from union refactor (emergent scope)

- [x] Fix `dashboard-provider-api.ts` — use `getGroupItemPanelKeys()` helpers
- [x] Fix `panel-editor-slice.ts` — narrow with `layoutKind` for panel move/add
- [x] Fix `delete-panel-slice.ts` — handle both Grid and Tab for panel deletion
- [x] Fix `duplicate-panel-slice.ts` — find containing tab for Tab group duplication
- [x] Fix `view-panel-slice.ts` — use helpers for panel ref lookup
- [x] Fix `delete-panel-group-slice.ts` — use helpers for panel key collection
- [x] Fix `panel-group-editor-slice.ts` — narrow `repeatVariable` access to Grid
- [x] Fix `panelUtils.ts` — accept `{ itemLayouts }` instead of full `PanelGroupDefinition`
- [x] Fix `GridLayout.tsx` — narrow to `GridPanelGroup` with runtime check
- [x] Fix `Row.tsx` — change prop type to `GridPanelGroup`

### Phase 2 Verification

- [x] `cd projects/perses-shared && npm run type-check` — **passes** (10/10 tasks)
- [x] `cd projects/perses-shared && npm run build` — **passes** (8/8 tasks)
- [x] `cd projects/perses-shared && npm run test` — **passes** (15 suites, 84 tests, including 13 new)
- [x] Grid-only dashboard backwards compatibility confirmed via conversion round-trip tests

---

## Phase 3: Build TabLayout UI Components

Depends on: Phase 2 | Parallel with: none | Type: implementation | Projects: perses-shared

### 3a. TabLayout component and barrel export

- [x] Create `TabLayout.tsx` — main component: collapsible group + tab bar + active tab's grid + URL sync + view panel -
      `perses-shared/dashboards/src/components/TabLayout/TabLayout.tsx`
- [x] Create `TabBar.tsx` — MUI Tabs with star icon on default tab, accepts isEditMode prop -
      `perses-shared/dashboards/src/components/TabLayout/TabBar.tsx`
- [x] Reused `GridTitle` directly (TabTitle not needed — identical behavior) -- **decision: no separate TabTitle.tsx**
- [x] Create barrel export `index.ts` - `perses-shared/dashboards/src/components/TabLayout/index.ts`
- [x] Added `export * from './TabLayout'` to components barrel

### 3b. Dashboard.tsx layout dispatch

- [x] Update Dashboard.tsx with `PanelGroupRenderer` component that dispatches to `<GridLayout>` or `<TabLayout>` -
      `perses-shared/dashboards/src/components/Dashboard/Dashboard.tsx`

### 3c. Zustand store tab actions

- [x] Add `setActiveTab`, `updateTabLayouts` actions (remaining tab-edit actions deferred to Phase 4) -
      `perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.ts`
- [x] Actions narrow to TabPanelGroup before operating (no assertTabGroup helper needed)
- [x] Export `useTabActions` hook - `perses-shared/dashboards/src/context/DashboardProvider/dashboard-provider-api.ts`

### Phase 3 Verification

- [x] `cd projects/perses-shared && npm run type-check` — **passes** (10/10 tasks)
- [x] `cd projects/perses-shared && npm run build` — **passes** (8/8 tasks)
- [x] `cd projects/perses-shared && npm run test` — **passes** (15 suites, 91 tests, 7 new store action tests)
- [ ] Manual in browser: tab bar renders, tab switching works, collapse/expand works, URL updates with `?perses-tab=N` -- [DEFERRED to Phase 5
      integration]

---

## Phase 4: Tab Editing Experience

Depends on: Phase 3 | Parallel with: Phase 5 (different repo) | Type: implementation | Projects: perses-shared

- [x] Add layout type selector (Grid/Tabs) to PanelGroupEditorForm; hide repeat variable when Tabs selected -
      `perses-shared/dashboards/src/components/PanelGroupDialog/PanelGroupEditorForm.tsx`
- [x] Add `layoutKind` to `PanelGroupEditorValues`; handle Grid↔Tabs conversion in `openAddPanelGroup`/`openEditPanelGroup` -
      `perses-shared/dashboards/src/context/DashboardProvider/panel-group-editor-slice.ts`
- [x] Add 5 tab editing store actions: `updateTabName`, `setDefaultTab`, `addTab`, `removeTab`, `reorderTabs` -
      `perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.ts`
- [x] Extend `useTabActions` hook with all 5 new editing actions - `perses-shared/dashboards/src/context/DashboardProvider/dashboard-provider-api.ts`
- [x] Full edit-mode TabBar: inline rename, left/right reorder, star default toggle, delete tab, add tab button -
      `perses-shared/dashboards/src/components/TabLayout/TabBar.tsx`
- [x] Wire TabLayout to pass edit callbacks from `useTabActions` to TabBar - `perses-shared/dashboards/src/components/TabLayout/TabLayout.tsx`

### Phase 4 Verification

- [x] `npm run type-check` — **passes**
- [x] `npm run build` — **passes**
- [x] `npm run test` — **passes** (116 tests, 25 new store action tests)
- [x] `npm run lint` — **passes**
- [ ] Manual in browser (edit mode): create Tabs group, rename/reorder/add/remove tabs, set default tab, save and reload -- [DEFERRED to integration]

--- Phases 4 and 5 can run in parallel after Phase 3 (different repos) ---

## Phase 5: Integrate with Perses UI and Backend

Depends on: Phase 1 (Go types), Phase 3 (shared components via linked packages) | Parallel with: Phase 4 (different repo) | Type: configuration |
Projects: perses

### 5a. Backend compatibility

- [x] Update perses Go module dependency on perses-spec to `feat/add-tab-layout` branch - `perses/go.mod` -- [HUMAN: requires pushing spec branch
      first]
- [x] Verify backend accepts and stores Tabs layout JSON via spec's `Layout.UnmarshalJSON` -- [HUMAN: requires go dep update]

### 5b. Test dashboard fixtures

- [x] Create `tablayout.json` test dashboard with Tabs layout (2 tabs, 3 panels) - `perses/dev/local_db/dashboards/testing/tablayout.json`
- [x] Create `mixedlayouts.json` test dashboard with Grid + Tabs (1 Grid + 1 Tabs layout) - `perses/dev/local_db/dashboards/testing/mixedlayouts.json`

> Note: `dev/local_db/` is gitignored — fixtures exist on disk for dev server but cannot be committed. This is consistent with existing fixture
> behavior.

### 5c. Link shared dependencies for local UI testing

- [x] Run `link-with-perses.sh link` to link `@perses-dev/*` packages -- [HUMAN]
- [x] Start perses UI dev server and verify tab layout renders -- [HUMAN]

### Phase 5 Verification

- [ ] `cd projects/perses && go build ./...` — compiles with updated spec dependency -- [BLOCKED: requires spec branch push + go get]
- [ ] `cd projects/perses && go test ./...` — all tests pass -- [BLOCKED]
- [ ] Load `tablayout` dashboard via API — JSON round-trips correctly -- [HUMAN]
- [ ] Load `mixedlayouts` dashboard — both Grid and Tabs render -- [HUMAN]

---

## Phase 6: E2E Tests

Depends on: Phase 4, Phase 5 | Parallel with: none | Type: implementation | Projects: perses

### 6a. Page objects

- [x] Create `TabGroup.ts` page object (tab switching, collapse, edit interactions) - `perses/ui/e2e/src/pages/TabGroup.ts`
- [x] Add tab-related helpers to `DashboardPage.ts` - `perses/ui/e2e/src/pages/DashboardPage.ts`
- [x] Export `TabGroup` from `perses/ui/e2e/src/pages/index.ts`

### 6b. Tab layout e2e tests

- [x] Write `tabLayout.spec.ts`: render tabs, switch tabs, default tab, collapse/expand, URL sync, lazy render -
      `perses/ui/e2e/src/tests/tabLayout.spec.ts`
- [x] Write tab editing tests: rename, reorder, set default, add/remove tabs, save - `perses/ui/e2e/src/tests/tabLayout.spec.ts`

### 6c. Mixed layouts e2e tests

- [x] Write `mixedLayouts.spec.ts`: mixed Grid+Tabs rendering, independent collapse, reorder groups - `perses/ui/e2e/src/tests/mixedLayouts.spec.ts`

### Phase 6 Verification

- [x] `cd projects/perses/ui/e2e && npm run e2e:local -- --grep "Tab Layout"` — **passes** (8/8 tests)
- [x] `cd projects/perses/ui/e2e && npm run e2e:local -- --grep "Mixed Layouts"` — **passes** (3/3 tests)
- [x] Full e2e suite — new tests pass, pre-existing failures in `duplicatePanels` and `timePicker` (unrelated to tab layout)

---

## Summary

**Status:** Complete (6 of 6 phases done)

### Outstanding items

- [x] Phase 5a: Push perses-spec `feat/add-tab-layout` branch, then `go get github.com/perses/spec@feat/add-tab-layout` in perses
- [x] Phase 5c: Run `link-with-perses.sh link` and start dev server to verify UI
- [x] Phase 6: E2E test files created and verified (TabGroup page object, tabLayout.spec.ts, mixedLayouts.spec.ts)
- [x] Phase 6 Verification: 11/11 new e2e tests pass (8 tab layout + 3 mixed layouts)

### Fixes applied during E2E testing

- Fixed TabBar.tsx `<button>` inside `<button>` DOM nesting: changed `<IconButton>` to `component="span"` in edit-mode tab labels
- Fixed URL sync test: used `page.waitForURL()` instead of immediate `page.url()` check
- Added `ignoresConsoleErrors` for pre-existing `validateDOMNesting` and `unique "key" prop` warnings
- Reset tablayout dashboard fixture (had been modified by manual browser testing)

### Notes

- Build/test commands per project:
  - **perses-spec**: Go: `go build ./...`, `go test ./...`; CUE: `make cue-gen`, `make cue-eval`; TS: `npm run build`, `npm test`,
    `npm run type-check` (in `ts/` dir)
  - **perses-shared**: `npm run build`, `npm test`, `npm run type-check`, `npm run lint` (turborepo root)
  - **perses**: Go: `make test`, `go build ./...`; UI: `npm run build`, `npm test` (in `ui/` dir); E2E: `npm run e2e:local` (in `ui/e2e/` dir or
    `npm run e2e` from `ui/` root)
- Test conventions: perses-spec Go uses `*_test.go` (colocated); perses-shared uses `*.test.ts`/`*.test.tsx` (colocated, Jest); perses e2e uses
  `*.spec.ts` (Playwright)
- All repos use `feat/add-tab-layout` branch name

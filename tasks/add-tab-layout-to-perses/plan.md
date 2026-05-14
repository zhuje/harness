# Plan: Add Tab Layout to Perses

## Problem

Complex monitoring dashboards require many panel groups (overview, utilization, network, storage, alerts). Today, authors must either pack everything
into one scrollable dashboard with collapsible sections, or split into separate dashboards losing shared variables and time range. A tab layout
provides a persistent navigation bar for switching between related panel groups without scrolling, while preserving shared context. See
[GitHub issue #4067](https://github.com/perses/perses/issues/4067).

## Current State

| Component                 | File / Location                                                                               | Current Behavior                                                                                                                             |
| ------------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Layout Go types           | `projects/perses-spec/go/dashboard/layout.go:24-145`                                          | Defines `LayoutKind` with only `"Grid"`, `Layout` struct with polymorphic unmarshal via `Kind` switch. `LayoutSpec` is `any`.                |
| Layout CUE (generated)    | `projects/perses-spec/cue/dashboard/layout_go_gen.cue`                                        | Generated from Go. Defines `#GridLayoutSpec`, `#GridItem`, `#LayoutKind` enum.                                                               |
| Layout CUE (patch)        | `projects/perses-spec/cue/dashboard/layout_patch.cue`                                         | Hand-written constraints: `#LayoutSpec: #GridLayoutSpec`, `#Layout` struct.                                                                  |
| Layout TS types           | `projects/perses-spec/ts/src/dashboard/layout.ts:16-38`                                       | `LayoutDefinition = GridDefinition` (union of one). `GridDefinition` has `kind: 'Grid'`, `spec` with `display?`, `items`, `repeatVariable?`. |
| Dashboard component       | `projects/perses-shared/dashboards/src/components/Dashboard/Dashboard.tsx:36-63`              | Iterates `panelGroupIds` and renders `<GridLayout>` for each group. No layout-type dispatch.                                                 |
| GridLayout component      | `projects/perses-shared/dashboards/src/components/GridLayout/GridLayout.tsx:33-100`           | Renders a single grid group: handles `repeatVariable`, delegates to `Row` with react-grid-layout.                                            |
| Row component             | `projects/perses-shared/dashboards/src/components/GridLayout/Row.tsx:46-156`                  | Renders `GridTitle` (collapse header), `Collapse` wrapper, `ResponsiveGridLayout` with panels. Uses `useViewPanelGroup` for fullscreen.      |
| GridTitle component       | `projects/perses-shared/dashboards/src/components/GridLayout/GridTitle.tsx:42-144`            | Renders collapse toggle, title text, edit-mode buttons (add panel, edit group, delete, move up/down).                                        |
| PanelGroupDefinition      | `projects/perses-shared/dashboards/src/model/PanelGroupDefinition.ts:64-72`                   | Runtime model: `id`, `isCollapsed`, `title?`, `repeatVariable?`, `itemLayouts`, `itemPanelKeys`. No `layoutKind` field.                      |
| panel-group-slice         | `projects/perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.ts:86-125` | `convertLayoutsToPanelGroups()`: iterates `layouts[]`, extracts items and panel keys. Hardcoded to GridDefinition.                           |
| useDashboard              | `projects/perses-shared/dashboards/src/context/useDashboard.tsx:114-158`                      | `convertPanelGroupsToLayouts()`: converts back to `GridDefinition[]`. Hardcoded `kind: 'Grid'`.                                              |
| PanelGroupEditorForm      | `projects/perses-shared/dashboards/src/components/PanelGroupDialog/PanelGroupEditorForm.tsx`  | Edits title, collapse state, repeat variable. No layout type selector.                                                                       |
| Test dashboard fixture    | `projects/perses/dev/local_db/dashboards/testing/panelgroups.json`                            | Single grid layout with one markdown panel, collapse open.                                                                                   |
| E2E test for panel groups | `projects/perses/ui/e2e/src/tests/panelGroups.spec.ts`                                        | Playwright tests: expand/collapse, edit name, add/remove/reorder groups. Uses `DashboardPage` and `PanelGroup` page objects.                 |

## Changes

### Phase 1: Define Tab Layout Types in perses-spec

**Dependency:** None **Parallel with:** None

#### Files Modified

| File                                                   | Change                                                                                                                                            |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `projects/perses-spec/go/dashboard/layout.go`          | Add `KindTabLayout LayoutKind = "Tabs"`, new types `TabItem`, `TabLayoutDisplay`, `TabLayoutSpec`. Update `layoutKindMap` and `unmarshal` switch. |
| `projects/perses-spec/cue/dashboard/layout_go_gen.cue` | Regenerate via `make cue-gen` (or manually add `#TabLayoutSpec`, `#TabItem`, `#KindTabLayout`).                                                   |
| `projects/perses-spec/cue/dashboard/layout_patch.cue`  | Update `#LayoutSpec` to union: `#GridLayoutSpec \| #TabLayoutSpec`. Update `#LayoutKind` enum.                                                    |
| `projects/perses-spec/ts/src/dashboard/layout.ts`      | Add `TabDefinition`, `TabItemDefinition` interfaces. Update `LayoutDefinition` to `GridDefinition \| TabDefinition`.                              |

#### Details

##### Go types

Add the new `"Tabs"` kind and its spec types:

```go
const (
    KindGridLayout LayoutKind = "Grid"
    KindTabLayout  LayoutKind = "Tabs"
)

var layoutKindMap = map[LayoutKind]bool{
    KindGridLayout: true,
    KindTabLayout:  true,
}

type TabItem struct {
    // Display name of the tab shown in the tab bar.
    Name string `json:"name" yaml:"name"`
    // The grid layout items within this tab.
    Items []GridItem `json:"items" yaml:"items"`
}

type TabLayoutDisplay struct {
    Title string `json:"title" yaml:"title"`
    // If Collapse is defined, the tab group will be rendered in a collapsible container.
    // If not defined, the tab group will be rendered expanded without the ability to collapse it.
    Collapse *GridLayoutCollapse `json:"collapse,omitempty" yaml:"collapse,omitempty"`
}

type TabLayoutSpec struct {
    Display    *TabLayoutDisplay `json:"display,omitempty" yaml:"display,omitempty"`
    // Ordered list of tabs. The first tab (or defaultTab index) is shown by default.
    Tabs       []TabItem `json:"tabs" yaml:"tabs"`
    // Zero-based index of the tab to show by default. Defaults to 0.
    DefaultTab int       `json:"defaultTab,omitempty" yaml:"defaultTab,omitempty"`
}
```

Update the `unmarshal` switch at line 136:

```go
switch tmpLayout.Kind {
case KindGridLayout:
    spec = &GridLayoutSpec{}
case KindTabLayout:
    spec = &TabLayoutSpec{}
}
```

##### CUE patch

Update `layout_patch.cue` to accept the union:

```cue
#LayoutKind: #enumLayoutKind

#LayoutSpec: #GridLayoutSpec | #TabLayoutSpec

#Layout: {
    kind: #LayoutKind @go(Kind)
    spec: #LayoutSpec @go(Spec)
}
```

After Go changes, run `make cue-gen` to regenerate `layout_go_gen.cue` with the new types. Then verify the patch file constraints match.

##### TypeScript types

```typescript
export type LayoutDefinition = GridDefinition | TabDefinition;

export interface TabDefinition {
  kind: 'Tabs';
  spec: {
    display?: {
      title: string;
      collapse?: {
        open: boolean;
      };
    };
    tabs: TabItemDefinition[];
    defaultTab?: number;
  };
}

export interface TabItemDefinition {
  name: string;
  items: GridItemDefinition[];
}
```

#### Phase 1 Verification

- `cd projects/perses-spec && go build ./...` — compiles without errors
- `cd projects/perses-spec && go test ./...` — all tests pass
- `cd projects/perses-spec && make cue-gen` — CUE files regenerate cleanly
- `cd projects/perses-spec/ts && npm run build && npm run type-check` — TS builds and type-checks
- Manual: verify a JSON dashboard with `kind: "Tabs"` deserializes correctly via a Go test

---

### Phase 2: Update perses-shared Runtime Model and Conversion

**Dependency:** Phase 1 (needs new TS types from `@perses-dev/spec`) **Parallel with:** None

#### Files Modified

| File                                                                                   | Change                                                                                                                                                      |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `projects/perses-shared/dashboards/src/model/PanelGroupDefinition.ts`                  | Refactor `PanelGroupDefinition` into a discriminated union: `PanelGroupBase` + `GridPanelGroup` \| `TabPanelGroup`. Add `TabState` type.                    |
| `projects/perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.ts` | Update `convertLayoutsToPanelGroups()` to dispatch on `layout.kind` and produce the correct union variant. Add tab-specific state initialization.           |
| `projects/perses-shared/dashboards/src/context/useDashboard.tsx`                       | Update `convertPanelGroupsToLayouts()` to dispatch on `group.layoutKind` and emit `TabDefinition` or `GridDefinition`. Return type to `LayoutDefinition[]`. |

#### Details

##### Link dependency for local testing

```bash
# Link perses-spec TS types into perses-shared for local development
cd projects/perses-shared && npm install ../perses-spec/ts
```

##### PanelGroupDefinition model

Refactor from a single flat interface into a discriminated union. This ensures type safety — you cannot access `tabs` on a Grid group or
`repeatVariable` on a Tab group without narrowing first. Adding a new layout type in the future means adding one new interface and one new union
member; the compiler will flag every location that needs updating.

```typescript
export interface TabState {
  name: string;
  itemLayouts: PanelGroupItemLayout[];
  itemPanelKeys: Record<PanelGroupItemLayoutId, string>;
}

interface PanelGroupBase {
  id: PanelGroupId;
  isCollapsed: boolean;
  title?: string;
  repeatedOriginId?: PanelGroupId;
}

export interface GridPanelGroup extends PanelGroupBase {
  layoutKind: 'Grid';
  itemLayouts: PanelGroupItemLayout[];
  itemPanelKeys: Record<PanelGroupItemLayoutId, string>;
  repeatVariable?: string;
}

export interface TabPanelGroup extends PanelGroupBase {
  layoutKind: 'Tabs';
  tabs: TabState[];
  defaultTab: number;
  activeTab: number;   // runtime-only, not persisted
}

export type PanelGroupDefinition = GridPanelGroup | TabPanelGroup;
```

**Backwards compatibility:** Existing code that accesses `group.itemLayouts` directly will get a type error, forcing an explicit `layoutKind` check.
For the existing `GridLayout` and `Row` components, narrow with `group.layoutKind === 'Grid'` (or assert via a helper) since they are only ever
rendered for Grid groups. The `createEmptyPanelGroup()` helper returns a `GridPanelGroup` to preserve current behavior for the "Add Panel Group" flow.

##### convertLayoutsToPanelGroups update

The function currently iterates layouts and always accesses `layout.spec.items`. Update to dispatch on `layout.kind`:

```typescript
for (const layout of layouts) {
  const panelGroupId = generateId();

  if (layout.kind === 'Grid') {
    // Existing grid conversion logic — produces GridPanelGroup
    const itemLayouts: PanelGroupItemLayout[] = [];
    const itemPanelKeys: GridPanelGroup['itemPanelKeys'] = {};
    for (const item of layout.spec.items) {
      const id = generateId().toString();
      itemLayouts.push({ i: id, w: item.width, h: item.height, x: item.x, y: item.y });
      itemPanelKeys[id] = getPanelKeyFromRef(item.content);
    }
    const group: GridPanelGroup = {
      id: panelGroupId,
      layoutKind: 'Grid',
      isCollapsed: layout.spec.display?.collapse?.open === false,
      repeatVariable: layout.spec.repeatVariable,
      title: layout.spec.display?.title,
      itemLayouts,
      itemPanelKeys,
    };
    panelGroups[panelGroupId] = group;
  } else if (layout.kind === 'Tabs') {
    // New tab conversion — produces TabPanelGroup
    const tabs: TabState[] = layout.spec.tabs.map((tab) => {
      const tabItemLayouts: PanelGroupItemLayout[] = [];
      const tabItemPanelKeys: Record<string, string> = {};
      for (const item of tab.items) {
        const id = generateId().toString();
        tabItemLayouts.push({ i: id, w: item.width, h: item.height, x: item.x, y: item.y });
        tabItemPanelKeys[id] = getPanelKeyFromRef(item.content);
      }
      return { name: tab.name, itemLayouts: tabItemLayouts, itemPanelKeys: tabItemPanelKeys };
    });
    const group: TabPanelGroup = {
      id: panelGroupId,
      layoutKind: 'Tabs',
      isCollapsed: layout.spec.display?.collapse?.open === false,
      title: layout.spec.display?.title,
      tabs,
      defaultTab: layout.spec.defaultTab ?? 0,
      activeTab: layout.spec.defaultTab ?? 0,
    };
    panelGroups[panelGroupId] = group;
  }
  panelGroupIdOrder.push(panelGroupId);
}
```

##### convertPanelGroupsToLayouts update

Change return type from `GridDefinition[]` to `LayoutDefinition[]` and dispatch on `layoutKind`:

```typescript
function convertPanelGroupsToLayouts(
  panelGroups: Record<number, PanelGroupDefinition>,
  panelGroupOrder: PanelGroupId[]
): LayoutDefinition[] {
  const layouts: LayoutDefinition[] = [];
  for (const groupOrderId of panelGroupOrder) {
    const group = panelGroups[groupOrderId];
    if (group === undefined) throw new Error('panel group not found');

    switch (group.layoutKind) {
      case 'Tabs': {
        // Narrowed to TabPanelGroup — group.tabs is guaranteed to exist
        layouts.push({
          kind: 'Tabs',
          spec: {
            display: group.title ? { title: group.title, collapse: { open: !group.isCollapsed } } : undefined,
            tabs: group.tabs.map((tab) => ({
              name: tab.name,
              items: tab.itemLayouts.map((layout) => {
                const panelKey = tab.itemPanelKeys[layout.i];
                if (!panelKey) throw new Error(`Missing panel key of layout ${layout.i}`);
                return { x: layout.x, y: layout.y, width: layout.w, height: layout.h, content: createPanelRef(panelKey) };
              }),
            })),
            defaultTab: group.defaultTab,
          },
        });
        break;
      }
      case 'Grid': {
        // Narrowed to GridPanelGroup — existing serialization (unchanged)
        const { title, isCollapsed, repeatVariable, itemLayouts, itemPanelKeys } = group;
        ...
        break;
      }
    }
  }
  return layouts;
}
```

Using `switch` on the discriminant enables exhaustive checking — if a new layout variant is added to the union without a corresponding `case`, the
compiler will flag it.

#### Phase 2 Verification

- `cd projects/perses-shared && npm run type-check` — no type errors
- `cd projects/perses-shared && npm run build` — builds successfully
- `cd projects/perses-shared && npm run test` — existing unit tests pass
- Manual: verify that loading a dashboard JSON with only Grid layouts still works identically (backwards compatibility)

---

### Phase 3: Build TabLayout UI Components

**Dependency:** Phase 2 **Parallel with:** None

#### Files Modified

| File                                                                                        | Change                                                                                              |
| ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `projects/perses-shared/dashboards/src/components/TabLayout/TabLayout.tsx`                  | **New file.** Main TabLayout component: renders tab bar + active tab's grid.                        |
| `projects/perses-shared/dashboards/src/components/TabLayout/TabBar.tsx`                     | **New file.** Tab bar with MUI Tabs, edit-mode tab name editing, reordering, default tab indicator. |
| `projects/perses-shared/dashboards/src/components/TabLayout/TabTitle.tsx`                   | **New file.** Collapsible header for the tab group (similar to GridTitle).                          |
| `projects/perses-shared/dashboards/src/components/TabLayout/index.ts`                       | **New file.** Barrel exports.                                                                       |
| `projects/perses-shared/dashboards/src/components/Dashboard/Dashboard.tsx`                  | Add layout-type dispatch: render `<GridLayout>` or `<TabLayout>` based on `layoutKind`.             |
| `projects/perses-shared/dashboards/src/context/DashboardProvider/panel-group-slice.ts`      | Add `setActiveTab` and `updateTabLayouts` actions.                                                  |
| `projects/perses-shared/dashboards/src/context/DashboardProvider/dashboard-provider-api.ts` | Export new hooks: `useActiveTab`, `useTabActions`.                                                  |

#### Details

##### TabLayout component

The main component renders a collapsible group with a tab bar and the active tab's grid content:

```
┌─ TabTitle (collapse toggle + title + edit buttons) ──────────────┐
│  [ Tab 1 ]  [ Tab 2* ]  [ Tab 3 ]   (* = default)               │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  ResponsiveGridLayout (active tab's panels)               │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐                  │   │
│  │  │ Panel A  │ │ Panel B  │ │ Panel C  │                  │   │
│  │  └──────────┘ └──────────┘ └──────────┘                  │   │
│  └────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

Key behaviors:

- **Lazy rendering**: Only the active tab's grid is mounted. Use `unmountOnExit` on tab panels so inactive tab content is unmounted.
- **URL sync**: Active tab index synced to URL query param `perses-tab` (e.g., `?perses-tab=1`). Namespaced to avoid collisions when Perses dashboards
  are embedded in other apps. Use `useSearchParams()` from React Router.
- **Collapse**: Same behavior as GridLayout — if `display.collapse` is defined, the tab group is collapsible; if omitted, it renders expanded without
  collapse ability. Uses the same MUI `Collapse` pattern as `Row.tsx`.
- **Tab switching**: Clicking a tab updates `activeTab` in the Zustand store and the URL query param.

##### TabBar component (edit mode)

In edit mode, the tab bar provides:

- **Rename tabs**: Click tab label to make it editable (inline `TextField`).
- **Reorder tabs**: Drag-and-drop tabs using `@dnd-kit/core` (already commonly used with MUI), or simpler left/right arrow buttons per tab.
- **Set default tab**: Right-click or menu option on a tab to mark it as default (renders a star/dot indicator).
- **Add/remove tabs**: "+" button at the end of tab bar; delete button per tab.

##### Dashboard.tsx layout dispatch

The Dashboard component currently only uses `panelGroupIds` and always renders `<GridLayout>`. Update it to also read each group's `layoutKind` and
dispatch to the correct component. Use a `switch` on `layoutKind` so the compiler flags any missing variant when new layout types are added:

```tsx
{!isEmpty &&
  panelGroupIds.map((panelGroupId) => {
    const group = panelGroups[panelGroupId];
    if (!group) return null;
    switch (group.layoutKind) {
      case 'Tabs':
        return (
          <TabLayout
            key={panelGroupId}
            panelGroupId={panelGroupId}
            panelOptions={panelOptions}
            panelFullHeight={panelFullHeight}
          />
        );
      case 'Grid':
        return (
          <GridLayout
            key={panelGroupId}
            panelGroupId={panelGroupId}
            panelOptions={panelOptions}
            panelFullHeight={panelFullHeight}
          />
        );
    }
  })}
```

This requires accessing `panelGroups` in the Dashboard component. Currently it only uses `panelGroupIds`. Add a `usePanelGroups()` hook or call
`usePanelGroup(id)` per iteration.

##### Zustand store updates

Add tab-specific actions to `PanelGroupSlice`. Each action implementation should narrow the group to `TabPanelGroup` and throw if the group is not a
Tabs layout — this catches misuse at runtime even though the type system prevents it at compile time in well-typed callers:

```typescript
setActiveTab: (panelGroupId: PanelGroupId, tabIndex: number) => void;
updateTabLayouts: (panelGroupId: PanelGroupId, tabIndex: number, itemLayouts: PanelGroupItemLayout[]) => void;
updateTabName: (panelGroupId: PanelGroupId, tabIndex: number, name: string) => void;
setDefaultTab: (panelGroupId: PanelGroupId, tabIndex: number) => void;
addTab: (panelGroupId: PanelGroupId, name: string) => void;
removeTab: (panelGroupId: PanelGroupId, tabIndex: number) => void;
reorderTabs: (panelGroupId: PanelGroupId, fromIndex: number, toIndex: number) => void;
```

Helper for narrowing inside Zustand `set()` callbacks:

```typescript
function assertTabGroup(group: PanelGroupDefinition): asserts group is TabPanelGroup {
  if (group.layoutKind !== 'Tabs') {
    throw new Error(`Expected Tabs layout but got ${group.layoutKind}`);
  }
}
```

#### Phase 3 Verification

- `cd projects/perses-shared && npm run type-check` — no type errors
- `cd projects/perses-shared && npm run build` — builds successfully
- `cd projects/perses-shared && npm run test` — existing tests pass
- Manual in browser: load a dashboard with both Grid and Tabs layouts, verify:
  - Tab bar renders with correct tab names
  - Clicking tabs switches content
  - Only active tab's panels are rendered (check React DevTools)
  - Collapse/expand works for the tab group
  - URL updates with `?perses-tab=N` on tab switch

---

### Phase 4: Tab Editing Experience

**Dependency:** Phase 3 **Parallel with:** None

#### Files Modified

| File                                                                                                | Change                                                                                                           |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `projects/perses-shared/dashboards/src/components/PanelGroupDialog/PanelGroupEditorForm.tsx`        | Add layout type selector (`Grid` / `Tabs`). When `Tabs` is selected, show tab management UI.                     |
| `projects/perses-shared/dashboards/src/components/PanelGroupDialog/PanelGroupDialog.tsx`            | Pass layout kind through editor values.                                                                          |
| `projects/perses-shared/dashboards/src/context/DashboardProvider/panel-group-editor-slice.ts`       | Add `layoutKind` to `PanelGroupEditorValues`. Handle tab-specific values in `applyPanelGroupEditor`.             |
| `projects/perses-shared/dashboards/src/components/DashboardToolbar/AddGroupButton/` (or equivalent) | Update "Add Panel Group" flow to allow choosing between Grid and Tabs.                                           |
| `projects/perses-shared/dashboards/src/components/TabLayout/TabBar.tsx`                             | Finalize edit-mode interactions: inline rename, tab reorder buttons, default tab toggle, add/remove tab buttons. |

#### Details

##### PanelGroupEditorForm updates

Add a layout type selector at the top of the form:

```tsx
<FormControl fullWidth margin="normal">
  <TextField
    select
    required
    label="Layout Type"
    value={layoutKind}
    onChange={(e) => setLayoutKind(e.target.value as 'Grid' | 'Tabs')}
  >
    <MenuItem value="Grid">Grid</MenuItem>
    <MenuItem value="Tabs">Tabs</MenuItem>
  </TextField>
</FormControl>
```

When `Tabs` is selected, show additional fields:

- Default tab selector (dropdown of current tab names)
- Initial tab names (for new groups: start with "Tab 1")

When editing an existing group, changing from Grid to Tabs wraps the existing grid content into a single tab. Changing from Tabs to Grid flattens all
tab content into a single grid (with a confirmation dialog warning about losing tab structure).

##### Tab editing in TabBar

In edit mode, each tab in the tab bar shows:

- Click-to-edit tab name (inline `TextField` replacing the tab label)
- Left/right arrow buttons for reordering
- Star icon button to set as default tab
- Delete button (with confirmation if tab has panels)

A "+" button at the end of the tab bar adds a new empty tab.

#### Phase 4 Verification

- Manual in browser (edit mode):
  - Create a new panel group with "Tabs" layout type
  - Verify tabs appear with default "Tab 1" name
  - Rename tabs inline
  - Reorder tabs using arrow buttons
  - Set a different default tab
  - Add and remove tabs
  - Save dashboard and reload — verify tab configuration persists
  - Change existing Grid group to Tabs and vice versa

---

### Phase 5: Integrate with Perses UI and Backend

**Dependency:** Phase 1 (Go types), Phase 3 (shared components via linked packages) **Parallel with:** Phase 4 (different repo)

#### Files Modified

| File                                                                                    | Change                                                                                                                                                                                                |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `projects/perses/go/dashboard/dashboard.go` (or wherever the Go API imports spec types) | Ensure the perses API server imports the updated `perses-spec` Go module with `TabLayoutSpec`. No code changes needed if the API stores layouts as opaque JSON via the spec's `Layout.UnmarshalJSON`. |
| `projects/perses/dev/local_db/dashboards/testing/tablayout.json`                        | **New file.** Test dashboard fixture with Tabs layout for e2e tests.                                                                                                                                  |
| `projects/perses/dev/local_db/dashboards/testing/mixedlayouts.json`                     | **New file.** Test dashboard fixture with both Grid and Tabs layouts.                                                                                                                                 |

#### Details

##### Backend compatibility

The perses API server uses `dashboard.Layout` from perses-spec for JSON unmarshaling. Since we added `KindTabLayout` to the `unmarshal` switch in
Phase 1, the backend will automatically accept and store Tabs layouts. No additional backend changes are needed.

Update the perses Go module's dependency on `github.com/perses/spec` to pick up the new types from the `feat/add-tab-layout` branch:

```bash
cd projects/perses && go get github.com/perses/spec@feat/add-tab-layout && go mod tidy
```

This requires the spec branch to be pushed first. Before merge, update to the final spec release version or merged commit.

##### Link shared dependencies for local UI testing

Use the `link-with-perses.sh` script from perses-shared to link the `@perses-dev/*` packages into the perses UI for local development:

```bash
cd projects/perses-shared && ./scripts/link-with-perses/link-with-perses.sh link --perses ../perses
```

Then start the perses UI in linked mode:

```bash
cd projects/perses/ui/app && npm run start:shared
```

When done testing, including e2e test. unlink to restore original dependencies:

```bash
cd projects/perses-shared && ./scripts/link-with-perses/link-with-perses.sh unlink
```

##### Test dashboard fixtures

Create `tablayout.json`:

```json
{
  "kind": "Dashboard",
  "metadata": { "name": "tablayout", "project": "testing" },
  "spec": {
    "panels": {
      "panel1": { "kind": "Panel", "spec": { "display": { "name": "Panel 1" }, "plugin": { "kind": "Markdown", "spec": { "text": "# Tab 1 Panel" } } } },
      "panel2": { "kind": "Panel", "spec": { "display": { "name": "Panel 2" }, "plugin": { "kind": "Markdown", "spec": { "text": "# Tab 2 Panel" } } } },
      "panel3": { "kind": "Panel", "spec": { "display": { "name": "Panel 3" }, "plugin": { "kind": "Markdown", "spec": { "text": "# Tab 2 Second Panel" } } } }
    },
    "layouts": [
      {
        "kind": "Tabs",
        "spec": {
          "display": { "title": "My Tab Group", "collapse": { "open": true } },
          "tabs": [
            { "name": "Overview", "items": [{ "x": 0, "y": 0, "width": 24, "height": 6, "content": { "$ref": "#/spec/panels/panel1" } }] },
            { "name": "Details", "items": [
              { "x": 0, "y": 0, "width": 12, "height": 6, "content": { "$ref": "#/spec/panels/panel2" } },
              { "x": 12, "y": 0, "width": 12, "height": 6, "content": { "$ref": "#/spec/panels/panel3" } }
            ] }
          ],
          "defaultTab": 0
        }
      }
    ],
    "duration": "6h"
  }
}
```

Create `mixedlayouts.json` with one Grid layout + one Tabs layout to test mixed-mode rendering.

#### Phase 5 Verification

- `cd projects/perses && go build ./...` — compiles with updated spec dependency
- `cd projects/perses && go test ./...` — all tests pass
- Start perses dev server, load `tablayout` dashboard via API — verify JSON round-trips correctly
- Load mixed layouts dashboard — verify both Grid and Tabs render

---

### Phase 6: E2E Tests

**Dependency:** Phase 5 (test fixtures), Phase 3-4 (UI components) **Parallel with:** None

#### Files Modified

| File                                                    | Change                                                                                       |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `projects/perses/ui/e2e/src/pages/TabGroup.ts`          | **New file.** Page object for TabLayout interactions (tab switching, tab editing, collapse). |
| `projects/perses/ui/e2e/src/pages/DashboardPage.ts`     | Add tab-related helper methods: `getTabGroup()`, `addTabGroup()`, `editTabGroup()`.          |
| `projects/perses/ui/e2e/src/pages/index.ts`             | Export new `TabGroup` page object.                                                           |
| `projects/perses/ui/e2e/src/tests/tabLayout.spec.ts`    | **New file.** E2E tests for the Tabs layout feature.                                         |
| `projects/perses/ui/e2e/src/tests/mixedLayouts.spec.ts` | **New file.** E2E tests for dashboards with both Grid and Tabs layouts.                      |

#### Details

##### TabGroup page object

Follow the same pattern as `PanelGroup.ts`:

```typescript
export class TabGroup {
  readonly container: Locator;
  readonly header: Locator;
  readonly tabBar: Locator;
  readonly content: Locator;

  constructor(container: Locator) {
    this.container = container;
    this.header = container.getByTestId('tab-group-header');
    this.tabBar = container.getByRole('tablist');
    this.content = container.getByTestId('tab-group-content');
  }

  getTab(name: string): Locator {
    return this.tabBar.getByRole('tab', { name });
  }

  async switchToTab(name: string): Promise<void> {
    await this.getTab(name).click();
  }

  async isExpanded(): Promise<void> { ... }
  async isCollapsed(): Promise<void> { ... }
  async collapse(): Promise<void> { ... }
  async expand(): Promise<void> { ... }
}
```

##### tabLayout.spec.ts test cases

```typescript
test.describe('Dashboard: Tab Layout', () => {
  test('renders tabs with correct names', async ({ dashboardPage }) => { ... });
  test('switches between tabs', async ({ dashboardPage }) => { ... });
  test('shows default tab on load', async ({ dashboardPage }) => { ... });
  test('can collapse and expand tab group', async ({ dashboardPage }) => { ... });
  test('URL updates with perses-tab query param', async ({ dashboardPage }) => { ... });
  test('lazy renders only active tab content', async ({ dashboardPage }) => { ... });
});

test.describe('Dashboard: Tab Layout Editing', () => {
  test('can rename tabs', async ({ dashboardPage }) => { ... });
  test('can reorder tabs', async ({ dashboardPage }) => { ... });
  test('can set default tab', async ({ dashboardPage }) => { ... });
  test('can add and remove tabs', async ({ dashboardPage }) => { ... });
  test('can add panel to specific tab', async ({ dashboardPage }) => { ... });
  test('saves tab layout changes', async ({ dashboardPage }) => { ... });
});
```

##### mixedLayouts.spec.ts test cases

```typescript
test.describe('Dashboard: Mixed Layouts', () => {
  test('renders both Grid and Tabs layouts on same dashboard', async ({ dashboardPage }) => { ... });
  test('grid and tab groups can be independently collapsed', async ({ dashboardPage }) => { ... });
  test('can reorder mixed layout groups', async ({ dashboardPage }) => { ... });
});
```

#### Phase 6 Verification

- `cd projects/perses/ui/e2e && npx playwright test src/tests/tabLayout.spec.ts` — all tab layout tests pass
- `cd projects/perses/ui/e2e && npx playwright test src/tests/mixedLayouts.spec.ts` — all mixed layout tests pass
- `cd projects/perses/ui/e2e && npx playwright test` — full e2e suite passes (no regressions)

---

## PR Strategy

| PR | Repository    | Branch                | Description                                                                     | Dependencies                                                |
| -- | ------------- | --------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| 1  | perses-spec   | `feat/add-tab-layout` | Add `Tabs` layout kind: Go types, CUE regeneration, CUE patch, TypeScript types | None                                                        |
| 2  | perses-shared | `feat/add-tab-layout` | Runtime model updates, TabLayout components, editing UI, Zustand store actions  | PR 1 published (or linked via `npm link`)                   |
| 3  | perses        | `feat/add-tab-layout` | Go module dependency update, test dashboard fixtures, e2e tests                 | PR 1 merged (Go dep), PR 2 merged or linked (UI components) |

All three repos use the same branch name `feat/add-tab-layout` for easy cross-repo tracking. During development, the perses repo can reference the
spec branch for Go dependencies via `go get github.com/perses/spec@feat/add-tab-layout` (or `go mod replace` for local development). Similarly,
perses-shared can install the spec TS package from the branch via `npm link` or a git dependency. PRs 1 and 2 can be reviewed in parallel. PR 3
depends on both being merged or at least having their changes available.

## Verification

End-to-end verification mapped to the spec's acceptance criteria:

- **"New Tabs layout that can group panels, panels inside each tab arranged and resized inside a grid"** — Load `tablayout` test dashboard, verify tab
  bar renders, switch tabs, verify each tab shows its panels in a react-grid-layout grid. In edit mode, drag/resize panels within a tab.

- **"Whole tabs group can be collapsed or expanded"** — On `tablayout` dashboard, click the collapse toggle on the tab group header. Verify tab bar
  and content collapse. Click again to expand. Verify collapse state persists after save.

- **"Dashboard can support both Grid and Tabs layouts simultaneously"** — Load `mixedlayouts` test dashboard. Verify both a Grid section and a Tabs
  section render on the same page. Verify independent collapse and interaction.

- **"While editing, tab display names can be changed, tabs can be reordered, default tab can be defined"** — Enter edit mode on `tablayout` dashboard.
  Rename a tab. Reorder tabs. Set a non-first tab as default. Save. Reload. Verify the default tab is shown first, names are correct, order is
  preserved.

- **"New e2e tests exist in perses ui to validate the new layout with testing dashboards"** — `tabLayout.spec.ts` and `mixedLayouts.spec.ts` pass in
  the Playwright suite at `projects/perses/ui/e2e/`.

## Risks

| Risk                                                                  | Impact                                                                | Mitigation                                                                                                                               |
| --------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `@perses-dev/spec` version mismatch between perses-shared and perses  | Build failures, runtime type errors                                   | Pin exact spec version in all consumers. Use `npm link` during development.                                                              |
| `convertLayoutsToPanelGroups` regression for existing Grid dashboards | All existing dashboards break                                         | Add `layoutKind` defaulting to `'Grid'`. Existing code paths unchanged. Add regression tests with existing dashboard fixtures.           |
| react-grid-layout interactions inside tabs (lazy mount/unmount)       | Layout calculations wrong when tab becomes visible for the first time | Force react-grid-layout to recalculate on tab activation. May need `onWidthChange` trigger after mount.                                  |
| URL `?perses-tab=` param conflicts with host app query params         | Tab state lost or overwrites other params                             | Namespaced as `perses-tab` to avoid collisions in embedded contexts. Use `URLSearchParams` to merge, not replace.                        |
| Tab reordering complexity in edit mode                                | Poor UX, hard to implement drag-and-drop on tab bar                   | Start with simple left/right arrow buttons per tab. Drag-and-drop can be added later as an enhancement.                                  |
| CUE generation drift between manual patch and auto-generated files    | CI validation failures in perses-spec                                 | Run `make cue-gen` after Go changes. Verify the patch file's union constraint matches the generated enum.                                |
| Perses Go module dependency update timing                             | PR 3 blocked until perses-spec is released                            | Use `go get github.com/perses/spec@feat/add-tab-layout` to reference the branch directly. Update to the merged commit before PR 3 merge. |

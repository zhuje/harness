# Plan: Add Alert Manager Datasource Plugin to Perses

## Problem

Perses currently supports Prometheus, Loki, Tempo, and Pyroscope as datasource plugins, covering metrics, logs, traces, and profiling. To complete the
troubleshooting experience, Perses needs Alert Manager support so users can visualize, filter, and manage alerts and silences directly within
dashboards and explore pages. This is especially critical for multi-cluster environments where each cluster has its own Alert Manager instance and
operators need a unified view.

The existing plugin system has query types for time series, traces, profiles, and logs, but alerts and silences have fundamentally different data
structures (label-based records with status, matchers, and lifecycle states). A new query type must be added to the spec and plugin system before the
Alert Manager plugin can be built.

## Current State

| Component                | File / Location                                    | Current Behavior                                                                                                                                                                   |
| ------------------------ | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Query type registry (TS) | `perses-spec/ts/src/dashboard/query-type/query.ts` | Defines `QueryType` interface with `TimeSeriesQuery`, `TraceQuery`, `ProfileQuery`, `LogQuery`. No alert/silence types.                                                            |
| Query type registry (Go) | `perses-spec/go/dashboard/dashboard.go`            | Defines `Query` and `QuerySpec` structs. Query kinds are plugin-driven, no alert-specific types.                                                                                   |
| Supported plugins (TS)   | `perses-shared/plugin-system/src/model/plugins.ts` | `SupportedPlugins` interface lists `TimeSeriesQuery`, `TraceQuery`, `ProfileQuery`, `LogQuery`, `Datasource`, `Panel`, `Variable`, `Explore`. No `AlertsQuery` or `SilencesQuery`. |
| Table component          | `perses-shared/components/src/Table/Table.tsx`     | Generic table with TanStack React Table, virtual scrolling, fuzzy search, `getSubRows` for hierarchy. No built-in group-by or expand/collapse-all controls.                        |
| Plugin modules           | `perses-plugins/`                                  | Contains prometheus, loki, tempo, pyroscope, clickhouse, victorialogs plugins. No alert-manager module.                                                                            |
| Plugin registry          | `perses/scripts/plugin/plugin.yaml`                | Lists all official plugins with name and version. No AlertManager entry.                                                                                                           |
| Datasource proxy         | `perses/pkg/model/api/v1/datasource/http/http.go`  | HTTP proxy with URL, allowedEndpoints, headers, and secret reference. Can be reused for Alert Manager.                                                                             |

## Changes

### Phase 1: Define Alert Manager Query Types in perses-spec

**Dependency:** None **Parallel with:** None

#### Files Modified

| File                                                        | Change                                                                                                                             |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `perses-spec/go/dashboard/alerts.go`                        | **New file.** Define Go types for `AlertsData` and `SilencesData` query result structures                                          |
| `perses-spec/ts/src/dashboard/query-type/alerts-data.ts`    | **New file.** TypeScript types for alert data: `Alert`, `AlertStatus`, `AlertsData`                                                |
| `perses-spec/ts/src/dashboard/query-type/silences-data.ts`  | **New file.** TypeScript types for silence data: `Silence`, `SilenceStatus`, `Matcher`, `SilencesData`                             |
| `perses-spec/ts/src/dashboard/query-type/alerts-queries.ts` | **New file.** `AlertsQueryDefinition` and `SilencesQueryDefinition` type aliases following the `TimeSeriesQueryDefinition` pattern |
| `perses-spec/ts/src/dashboard/query-type/query.ts`          | Add `AlertsQuery: AlertsData` and `SilencesQuery: SilencesData` to the `QueryType` interface                                       |
| `perses-spec/ts/src/dashboard/query-type/index.ts`          | Export new alert and silence query types                                                                                           |
| `perses-spec/ts/src/dashboard/index.ts`                     | Export new query types if not already re-exported                                                                                  |
| `perses-spec/ts/src/index.ts`                               | Ensure new types are exported from the package root                                                                                |

#### Details

##### Go types (source of truth)

Create `perses-spec/go/dashboard/alerts.go` with:

```go
package dashboard

// AlertStatus represents the state of an alert.
type AlertStatus struct {
    State       string   `json:"state" yaml:"state"`             // "active", "suppressed", "unprocessed"
    SilencedBy  []string `json:"silencedBy" yaml:"silencedBy"`
    InhibitedBy []string `json:"inhibitedBy" yaml:"inhibitedBy"`
    MutedBy     []string `json:"mutedBy" yaml:"mutedBy"`
}

// Receiver represents an alert receiver.
type Receiver struct {
    Name string `json:"name" yaml:"name"`
}

// Alert represents a single alert from Alert Manager (matches gettableAlert in API v2).
type Alert struct {
    Labels       map[string]string `json:"labels" yaml:"labels"`
    Annotations  map[string]string `json:"annotations" yaml:"annotations"`
    Receivers    []Receiver        `json:"receivers" yaml:"receivers"`
    Status       AlertStatus       `json:"status" yaml:"status"`
    StartsAt     string            `json:"startsAt" yaml:"startsAt"`
    EndsAt       string            `json:"endsAt" yaml:"endsAt"`
    UpdatedAt    string            `json:"updatedAt" yaml:"updatedAt"`
    GeneratorURL string            `json:"generatorURL" yaml:"generatorURL"`
    Fingerprint  string            `json:"fingerprint" yaml:"fingerprint"`
}

// AlertsData is the query result type for AlertsQuery plugins.
type AlertsData struct {
    Alerts []Alert `json:"alerts" yaml:"alerts"`
}

// MatchType represents the type of a silence matcher.
type MatchType string

const (
    MatchEqual    MatchType = "="
    MatchNotEqual MatchType = "!="
    MatchRegexp   MatchType = "=~"
    MatchNotRegexp MatchType = "!~"
)

// Matcher represents a silence matcher.
type Matcher struct {
    Name    string    `json:"name" yaml:"name"`
    Value   string    `json:"value" yaml:"value"`
    IsEqual bool      `json:"isEqual" yaml:"isEqual"`
    IsRegex bool      `json:"isRegex" yaml:"isRegex"`
}

// SilenceStatus represents the state of a silence.
type SilenceStatus struct {
    State string `json:"state" yaml:"state"` // "active", "expired", "pending"
}

// Silence represents a single silence from Alert Manager (matches gettableSilence in API v2).
type Silence struct {
    ID          string            `json:"id" yaml:"id"`
    Matchers    []Matcher         `json:"matchers" yaml:"matchers"`
    StartsAt    string            `json:"startsAt" yaml:"startsAt"`
    EndsAt      string            `json:"endsAt" yaml:"endsAt"`
    CreatedBy   string            `json:"createdBy" yaml:"createdBy"`
    Comment     string            `json:"comment" yaml:"comment"`
    Annotations map[string]string `json:"annotations" yaml:"annotations"`
    Status      SilenceStatus     `json:"status" yaml:"status"`
    UpdatedAt   string            `json:"updatedAt" yaml:"updatedAt"`
}

// SilencesData is the query result type for SilencesQuery plugins.
type SilencesData struct {
    Silences []Silence `json:"silences" yaml:"silences"`
}
```

After defining Go types, run `make cue-gen` to generate CUE definitions, then add `_patch.cue` files if constraints are lost in translation.

##### TypeScript types

Follow the pattern in `time-series-queries.ts`. The key types:

**`alerts-data.ts`:**

```typescript
export interface AlertStatus {
  state: 'active' | 'suppressed' | 'unprocessed';
  silencedBy: string[];
  inhibitedBy: string[];
  mutedBy: string[];
}

export interface Receiver {
  name: string;
}

export interface Alert {
  labels: Record<string, string>;
  annotations: Record<string, string>;
  receivers: Receiver[];
  status: AlertStatus;
  startsAt: string;
  endsAt: string;
  updatedAt: string;
  generatorURL: string;
  fingerprint: string;
}

export interface AlertsData {
  alerts: Alert[];
}
```

**`silences-data.ts`:**

```typescript
export interface Matcher {
  name: string;
  value: string;
  isEqual: boolean;
  isRegex: boolean;
}

export interface SilenceStatus {
  state: 'active' | 'expired' | 'pending';
}

export interface Silence {
  id: string;
  matchers: Matcher[];
  startsAt: string;
  endsAt: string;
  createdBy: string;
  comment: string;
  annotations: Record<string, string>;
  status: SilenceStatus;
  updatedAt: string;
}

export interface SilencesData {
  silences: Silence[];
}
```

**`alerts-queries.ts`:**

```typescript
import { QueryDefinition } from './query';
import { UnknownSpec } from '../../common';

export type AlertsQueryDefinition<PluginSpec = UnknownSpec> = QueryDefinition<'AlertsQuery', PluginSpec>;
export type SilencesQueryDefinition<PluginSpec = UnknownSpec> = QueryDefinition<'SilencesQuery', PluginSpec>;
```

**`query.ts` update:**

```typescript
export interface QueryType {
  TimeSeriesQuery: TimeSeriesData;
  TraceQuery: TraceData;
  ProfileQuery: ProfileData;
  LogQuery: LogData;
  AlertsQuery: AlertsData;     // new
  SilencesQuery: SilencesData;  // new
}
```

#### Phase 1 Verification

- `cd projects/perses-spec && go build ./...` passes
- `cd projects/perses-spec && make cue-gen` succeeds
- `cd projects/perses-spec/ts && npm run build` succeeds
- `cd projects/perses-spec/ts && npm run type-check` passes
- Confirm `AlertsData` and `SilencesData` are exported from the package

---

### Phase 2: Add Plugin System Support and HierarchicalTable to perses-shared

**Dependency:** Phase 1 (needs `AlertsData` and `SilencesData` types from `@perses-dev/spec` — resolved via local `npm link` after building
perses-spec on its branch) **Parallel with:** None

#### Phase 2A: Add AlertsQuery and SilencesQuery Plugin Types

##### Files Modified

| File                                                           | Change                                                                                         |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `perses-shared/plugin-system/src/model/alerts-queries.ts`      | **New file.** Define `AlertsQueryPlugin` interface following `TimeSeriesQueryPlugin` pattern   |
| `perses-shared/plugin-system/src/model/silences-queries.ts`    | **New file.** Define `SilencesQueryPlugin` interface following `TimeSeriesQueryPlugin` pattern |
| `perses-shared/plugin-system/src/model/plugins.ts`             | Add `AlertsQuery` and `SilencesQuery` to `SupportedPlugins` interface                          |
| `perses-shared/plugin-system/src/model/index.ts`               | Export new query plugin types                                                                  |
| `perses-shared/plugin-system/src/runtime/DataQueriesProvider/` | Update to handle `AlertsQuery` and `SilencesQuery` query kinds when dispatching data fetches   |

##### Details

**`alerts-queries.ts`** follows `time-series-queries.ts`:

```typescript
import { Plugin, PluginDependencies } from './plugin-base';
import { AlertsData } from '@perses-dev/spec';

export interface AlertsQueryContext {
  variableState: VariableStateMap;
  datasourceStore: DatasourceStore;
}

export interface AlertsQueryPlugin<Spec = UnknownSpec> extends Plugin<Spec> {
  getAlertsData: (spec: Spec, ctx: AlertsQueryContext, abortSignal?: AbortSignal) => Promise<AlertsData>;
  dependsOn?: (spec: Spec, ctx: AlertsQueryContext) => PluginDependencies;
}
```

Same pattern for `SilencesQueryPlugin` with `getSilencesData` returning `SilencesData`.

The `DataQueriesProvider` (or equivalent runtime component) must be updated to recognize `AlertsQuery` and `SilencesQuery` as valid query kinds and
dispatch them to the appropriate plugin's `getAlertsData` / `getSilencesData` methods.

#### Phase 2B: Add HierarchicalTable Component

##### Files Modified

| File                                                                               | Change                                                                                        |
| ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `perses-shared/components/src/HierarchicalTable/HierarchicalTable.tsx`             | **New file.** Generic groupable/expandable table wrapping the existing `Table` component      |
| `perses-shared/components/src/HierarchicalTable/model/hierarchical-table-model.ts` | **New file.** Props interface for grouping config, group renderers, expand/collapse state     |
| `perses-shared/components/src/HierarchicalTable/HierarchicalTableToolbar.tsx`      | **New file.** Toolbar with group-by selector chips, expand/collapse all buttons, search       |
| `perses-shared/components/src/HierarchicalTable/hooks/useGrouping.ts`              | **New file.** Hook to transform flat data into grouped hierarchy based on configurable fields |
| `perses-shared/components/src/HierarchicalTable/index.ts`                          | **New file.** Barrel exports                                                                  |
| `perses-shared/components/src/index.ts`                                            | Export `HierarchicalTable`                                                                    |

##### Details

The `HierarchicalTable` is a data-agnostic component that:

1. Takes flat data + grouping configuration
2. Transforms data into a tree structure using `useGrouping` hook
3. Wraps the existing `Table` component, passing `getSubRows` for hierarchy
4. Adds a toolbar with:
   - Group-by field selector (multi-select chips with remove)
   - Expand all / Collapse all buttons
   - Search/filter (delegates to Table's fuzzy search)
5. Renders group header rows with summary info (count, status aggregation)

**Key props interface:**

```typescript
export interface HierarchicalTableProps<TData> {
  data: TData[];
  columns: Array<TableColumnConfig<TData>>;
  groupByFields: GroupByField[];           // available fields to group by
  defaultGroupBy?: string[];               // initial grouping
  getGroupKey: (item: TData, field: string) => string;  // extract group value
  renderGroupSummary?: (group: GroupNode<TData>, field: string) => ReactNode;
  renderGroupActions?: (group: GroupNode<TData>) => ReactNode;
  height: number;
  width: number | string;
  density?: TableDensity;
  // inherits other Table props
}

export interface GroupByField {
  field: string;
  label: string;
}

export interface GroupNode<TData> {
  key: string;
  field: string;
  value: string;
  items: TData[];
  children?: GroupNode<TData>[];
}
```

The `useGrouping` hook converts flat `TData[]` into a tree of `GroupNode<TData>[]` based on the selected group-by fields. Each group node has a
`subRows` getter that returns either child groups (for nested grouping) or leaf items.

#### Phase 2 Verification

- `cd projects/perses-shared && npm run build` succeeds
- `cd projects/perses-shared && npm run type-check` passes
- `cd projects/perses-shared && npm run test` passes
- `cd projects/perses-shared && npm run lint` passes
- `AlertsQueryPlugin` and `SilencesQueryPlugin` are exported from `@perses-dev/plugin-system`
- `HierarchicalTable` is exported from `@perses-dev/components`

---

### Phase 3: Create Alert Manager Plugin Module in perses-plugins

**Dependency:** Phase 2 (needs `AlertsQueryPlugin`, `SilencesQueryPlugin` from plugin-system and `HierarchicalTable` from components — resolved via
`link-with-perses.sh link --plugins` to link perses-shared into perses-plugins locally) **Parallel with:** None

This is the largest phase, creating the full `alert-manager` plugin module. The Prometheus plugin is the structural reference.

#### Files Modified

| File                                                                                                       | Change                                                                                        |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `perses-plugins/alert-manager/package.json`                                                                | **New file.** Plugin metadata with `perses.plugins` array                                     |
| `perses-plugins/alert-manager/rsbuild.config.ts`                                                           | **New file.** Module federation config exposing all plugin components                         |
| `perses-plugins/alert-manager/tsconfig.json`                                                               | **New file.** TypeScript configuration                                                        |
| `perses-plugins/alert-manager/src/index.ts`                                                                | **New file.** Main barrel export                                                              |
| `perses-plugins/alert-manager/src/bootstrap.tsx`                                                           | **New file.** Dev server bootstrap                                                            |
| `perses-plugins/alert-manager/src/getPluginModule.ts`                                                      | **New file.** Plugin module metadata loader                                                   |
| `perses-plugins/alert-manager/src/model/alertmanager-client.ts`                                            | **New file.** Alert Manager v2 API client                                                     |
| `perses-plugins/alert-manager/src/model/api-types.ts`                                                      | **New file.** Alert Manager v2 API response types                                             |
| `perses-plugins/alert-manager/src/plugins/types.ts`                                                        | **New file.** Plugin spec types (datasource, query)                                           |
| `perses-plugins/alert-manager/src/plugins/alertmanager-datasource.tsx`                                     | **New file.** Datasource plugin with editor                                                   |
| `perses-plugins/alert-manager/src/plugins/AlertManagerDatasourceEditor.tsx`                                | **New file.** Datasource configuration form                                                   |
| `perses-plugins/alert-manager/src/plugins/alertmanager-alerts-query/AlertManagerAlertsQuery.ts`            | **New file.** AlertsQuery plugin definition                                                   |
| `perses-plugins/alert-manager/src/plugins/alertmanager-alerts-query/get-alerts-data.ts`                    | **New file.** Query execution: fetch alerts from AM API                                       |
| `perses-plugins/alert-manager/src/plugins/alertmanager-alerts-query/AlertManagerAlertsQueryEditor.tsx`     | **New file.** Query builder UI (filter matchers, receiver, active/silenced/inhibited toggles) |
| `perses-plugins/alert-manager/src/plugins/alertmanager-silences-query/AlertManagerSilencesQuery.ts`        | **New file.** SilencesQuery plugin definition                                                 |
| `perses-plugins/alert-manager/src/plugins/alertmanager-silences-query/get-silences-data.ts`                | **New file.** Query execution: fetch silences from AM API                                     |
| `perses-plugins/alert-manager/src/plugins/alertmanager-silences-query/AlertManagerSilencesQueryEditor.tsx` | **New file.** Query builder UI (filter by state, matchers)                                    |
| `perses-plugins/alert-manager/src/plugins/alert-table/AlertTable.ts`                                       | **New file.** Panel plugin definition for alert table                                         |
| `perses-plugins/alert-manager/src/plugins/alert-table/AlertTablePanel.tsx`                                 | **New file.** Alert hierarchical table panel component                                        |
| `perses-plugins/alert-manager/src/plugins/alert-table/alert-table-model.ts`                                | **New file.** Column configs, group functions, status renderers                               |
| `perses-plugins/alert-manager/src/plugins/silence-table/SilenceTable.ts`                                   | **New file.** Panel plugin definition for silence table                                       |
| `perses-plugins/alert-manager/src/plugins/silence-table/SilenceTablePanel.tsx`                             | **New file.** Silence hierarchical table panel component                                      |
| `perses-plugins/alert-manager/src/plugins/silence-table/silence-table-model.ts`                            | **New file.** Column configs, group functions                                                 |
| `perses-plugins/alert-manager/src/explore/AlertManagerAlertsExplorer.tsx`                                  | **New file.** Explore page for querying alerts                                                |
| `perses-plugins/alert-manager/src/explore/AlertManagerSilencesExplorer.tsx`                                | **New file.** Explore page for managing silences                                              |
| `perses-plugins/alert-manager/src/explore/components/SilenceForm.tsx`                                      | **New file.** Create/edit silence form (matchers, duration, author, comment)                  |
| `perses-plugins/alert-manager/src/components/StatusBadge.tsx`                                              | **New file.** Firing/silenced/pending status badges                                           |
| `perses-plugins/alert-manager/src/components/MatchersList.tsx`                                             | **New file.** Display silence matchers as chips                                               |
| `perses-plugins/alert-manager/src/components/MatcherEditor.tsx`                                            | **New file.** Edit silence matchers (name, value, type)                                       |
| `perses-plugins/alert-manager/schemas/datasource/alertmanager.cue`                                         | **New file.** CUE schema for datasource spec                                                  |
| `perses-plugins/alert-manager/schemas/alertmanager-alerts-query/alertmanager-alerts-query.cue`             | **New file.** CUE schema for alerts query                                                     |
| `perses-plugins/alert-manager/schemas/alertmanager-silences-query/alertmanager-silences-query.cue`         | **New file.** CUE schema for silences query                                                   |

#### Details

##### 3.1 Plugin Registration (package.json)

```json
{
  "name": "@perses-dev/alert-manager-plugin",
  "version": "0.1.0",
  "perses": {
    "moduleName": "AlertManager",
    "moduleOrg": "perses-dev",
    "schemasPath": "schemas",
    "plugins": [
      {
        "kind": "Datasource",
        "spec": {
          "display": { "name": "Alert Manager Datasource" },
          "name": "AlertManagerDatasource"
        }
      },
      {
        "kind": "AlertsQuery",
        "spec": {
          "display": { "name": "Alert Manager Alerts Query" },
          "name": "AlertManagerAlertsQuery"
        }
      },
      {
        "kind": "SilencesQuery",
        "spec": {
          "display": { "name": "Alert Manager Silences Query" },
          "name": "AlertManagerSilencesQuery"
        }
      },
      {
        "kind": "Panel",
        "spec": {
          "display": { "name": "Alert Table" },
          "name": "AlertTable"
        }
      },
      {
        "kind": "Panel",
        "spec": {
          "display": { "name": "Silence Table" },
          "name": "SilenceTable"
        }
      },
      {
        "kind": "Explore",
        "spec": {
          "display": { "name": "Alert Manager Alerts Explorer" },
          "name": "AlertManagerAlertsExplorer"
        }
      },
      {
        "kind": "Explore",
        "spec": {
          "display": { "name": "Alert Manager Silences Explorer" },
          "name": "AlertManagerSilencesExplorer"
        }
      }
    ]
  }
}
```

##### 3.2 Alert Manager API Client

The client wraps the Alert Manager v2 REST API. Key methods:

```typescript
export interface AlertManagerClient {
  // Alerts
  getAlerts(params?: AlertsQueryParams, abortSignal?: AbortSignal): Promise<GettableAlert[]>;

  // Silences
  getSilences(params?: SilencesQueryParams, abortSignal?: AbortSignal): Promise<GettableSilence[]>;
  getSilence(id: string, abortSignal?: AbortSignal): Promise<GettableSilence>;
  createSilence(silence: PostableSilence, abortSignal?: AbortSignal): Promise<{ silenceID: string }>;
  deleteSilence(id: string, abortSignal?: AbortSignal): Promise<void>;

  // Health
  getStatus(abortSignal?: AbortSignal): Promise<AlertManagerStatus>;
}
```

**API endpoints (v2):**

- `GET /api/v2/alerts` - List alerts with optional filters (`filter[]`, `silenced`, `inhibited`, `active`, `unprocessed`, `receiver`)
- `GET /api/v2/silences` - List silences with optional `filter[]`
- `GET /api/v2/silence/{id}` - Get specific silence
- `POST /api/v2/silences` - Create or update a silence
- `DELETE /api/v2/silence/{id}` - Expire a silence
- `GET /api/v2/status` - Health check

The client uses Perses' built-in datasource proxy. The datasource spec configures an HTTP proxy pointing to the Alert Manager URL, and the client
sends requests through `/api/v1/proxy/...` routes.

##### 3.3 Datasource Plugin

```typescript
export const AlertManagerDatasource: DatasourcePlugin<AlertManagerDatasourceSpec, AlertManagerClient> = {
  createClient: (spec, options) => createAlertManagerClient(spec, options),
  OptionsEditorComponent: AlertManagerDatasourceEditor,
  createInitialOptions: () => ({
    directUrl: '',
  }),
};

export interface AlertManagerDatasourceSpec {
  directUrl?: string;
  proxy?: HTTPProxy;
}
```

The datasource editor form allows configuring:

- Direct URL to Alert Manager
- Or proxy configuration (URL, headers, secret reference)

##### 3.4 Alerts Query Plugin

```typescript
export const AlertManagerAlertsQuery: AlertsQueryPlugin<AlertManagerAlertsQuerySpec> = {
  getAlertsData,
  OptionsEditorComponent: AlertManagerAlertsQueryEditor,
  createInitialOptions: () => ({
    datasource: undefined,
    filters: [],
    active: true,
    silenced: true,
    inhibited: true,
  }),
};

export interface AlertManagerAlertsQuerySpec {
  datasource?: DatasourceSelectValue<AlertManagerDatasourceSelector>;
  filters?: string[];       // PromQL-style matchers: alertname="HighCPU"
  active?: boolean;
  silenced?: boolean;
  inhibited?: boolean;
  receiver?: string;
}
```

The `getAlertsData` function:

1. Resolves the datasource from the store
2. Creates the client
3. Calls `client.getAlerts()` with the spec's filter parameters
4. Transforms `GettableAlert[]` into `AlertsData`

##### 3.5 Silences Query Plugin

```typescript
export const AlertManagerSilencesQuery: SilencesQueryPlugin<AlertManagerSilencesQuerySpec> = {
  getSilencesData,
  OptionsEditorComponent: AlertManagerSilencesQueryEditor,
  createInitialOptions: () => ({
    datasource: undefined,
    filters: [],
  }),
};

export interface AlertManagerSilencesQuerySpec {
  datasource?: DatasourceSelectValue<AlertManagerDatasourceSelector>;
  filters?: string[];
}
```

##### 3.6 Alert Table Panel

The alert table panel wraps `HierarchicalTable` from `@perses-dev/components`:

```typescript
export const AlertTable: PanelPlugin<AlertTableOptions> = {
  PanelComponent: AlertTablePanel,
  supportedQueryTypes: ['AlertsQuery'],
  createInitialOptions: () => ({
    defaultGroupBy: ['alertname'],
  }),
};

export interface AlertDeduplicationConfig {
  mode: 'fingerprint' | 'labels';
  labels?: string[];  // used when mode is 'labels'; alerts matching on all listed labels are merged
}

export interface AlertTableOptions {
  defaultGroupBy?: string[];
  columns?: string[];             // which label columns to show
  deduplication?: AlertDeduplicationConfig;  // defaults to { mode: 'fingerprint' }
}
```

**Deduplication for multi-datasource aggregation:**

When multiple queries return alerts from different Alert Manager instances (e.g., multi-cluster), the same logical alert may appear in more than one
result set. The `deduplication` option controls how duplicates are detected and merged:

- **`fingerprint` mode (default):** Alerts with the same `fingerprint` across datasources are treated as the same alert. The panel keeps the instance
  with the most recent `updatedAt` and attaches a `_sources` metadata array listing all datasources that reported it. This works well when all
  clusters use identical alerting rules, since Alertmanager computes fingerprints deterministically from the label set.
- **`labels` mode:** Users specify a list of label names (e.g., `['alertname', 'namespace', 'pod']`). Alerts matching on all listed labels are
  considered duplicates. This is useful when clusters have different label sets (e.g., one adds a `region` label) that cause fingerprint divergence
  for what is logically the same alert.

When no `deduplication` is configured, the panel defaults to `{ mode: 'fingerprint' }`.

The `AlertTablePanel` component:

1. Receives `queryResults: Array<PanelData<AlertsData>>` (one per query/datasource)
2. Tags each alert with a `_datasource` metadata label identifying its source
3. Deduplicates across datasources using the configured `deduplication` strategy, keeping the most recent instance and tracking all sources
4. Extracts available label keys from all alerts for the group-by selector
5. Renders using `HierarchicalTable` with:
   - Default grouping by `alertname`
   - Group summary showing counts (N firing, M silenced)
   - Status badge column (firing/silenced/inhibited icons)
   - Label columns (cluster, namespace, severity, etc.)
   - Source indicator when an alert was reported by multiple datasources
   - Action buttons per alert row: "Silence" (opens silence form), "Runbook" (links to `runbook_url` annotation)
   - Action button per group: "Silence Group" (pre-fills matchers for the group)

##### 3.7 Silence Table Panel

Similar to alert table but for silences:

```typescript
export const SilenceTable: PanelPlugin<SilenceTableOptions> = {
  PanelComponent: SilenceTablePanel,
  supportedQueryTypes: ['SilencesQuery'],
  createInitialOptions: () => ({
    defaultGroupBy: ['status'],
  }),
};
```

The panel groups silences by status (active/expired/pending) and displays:

- Matchers (as chips)
- Creator
- Duration (starts at / ends at)
- Comment
- Actions: "Edit" (opens silence form), "Expire" (calls API to delete)

##### 3.8 Alerts Explore Plugin

The alerts explore page provides an interactive interface for querying and browsing alerts:

```typescript
export function AlertManagerAlertsExplorer(): ReactElement {
  // Uses MultiQueryEditor for building alert queries
  // Wraps results in DataQueriesProvider
  // Renders AlertTablePanel for results display
  // Supports query parameter persistence in URL
}
```

Features:

- Query builder with filter matchers, active/silenced/inhibited toggles
- Real-time results in the alert table
- Quick-silence action from alert rows

##### 3.9 Silences Explore Plugin

The silences explore page adds write operations for silence management:

```typescript
export function AlertManagerSilencesExplorer(): ReactElement {
  // Query builder for filtering silences
  // Results in silence table
  // "Create Silence" button opens SilenceForm
  // Edit/Expire actions on existing silences
}
```

The `SilenceForm` component:

- Matchers editor (add/remove matchers with name, value, type)
- Start time / End time (or duration)
- Creator (auto-filled from user context if available)
- Comment
- Submit: calls `client.createSilence()` for new, or with existing ID for edit
- Cancel: closes form

##### 3.10 Module Federation Config

```typescript
// rsbuild.config.ts
export default createConfigForPlugin({
  name: 'AlertManager',
  rsbuild: {
    server: { port: 3015 },  // unique dev server port
    plugins: [pluginReact()],
  },
  moduleFederation: {
    exposes: {
      './AlertManagerDatasource': './src/plugins/alertmanager-datasource.tsx',
      './AlertManagerAlertsQuery': './src/plugins/alertmanager-alerts-query/AlertManagerAlertsQuery.ts',
      './AlertManagerSilencesQuery': './src/plugins/alertmanager-silences-query/AlertManagerSilencesQuery.ts',
      './AlertTable': './src/plugins/alert-table/AlertTable.ts',
      './SilenceTable': './src/plugins/silence-table/SilenceTable.ts',
      './AlertManagerAlertsExplorer': './src/explore/AlertManagerAlertsExplorer.tsx',
      './AlertManagerSilencesExplorer': './src/explore/AlertManagerSilencesExplorer.tsx',
    },
    shared: {
      react: { requiredVersion: '18.2.0', singleton: true },
      'react-dom': { requiredVersion: '18.2.0', singleton: true },
      '@perses-dev/plugin-system': { singleton: true },
      '@perses-dev/components': { singleton: true },
      '@perses-dev/explore': { singleton: true },
    },
  },
});
```

##### 3.11 CUE Schemas

Schemas are placed in the `schemas/` directory and validate plugin specs at the backend level.

**`schemas/datasource/alertmanager.cue`:**

```cue
package alertmanager

#AlertManagerDatasource: {
    kind: "AlertManagerDatasource"
    spec: {
        directUrl?: string
        proxy?: {
            kind: "httpproxy"
            spec: {
                url: string
                allowedEndpoints?: [...{
                    method: string
                    endpointPattern: string
                }]
                headers?: [string]: string
                secret?: string
            }
        }
    }
}
```

#### Phase 3 Verification

- `cd projects/perses-plugins/alert-manager && npm install` succeeds
- `cd projects/perses-plugins/alert-manager && npm run build` succeeds
- `cd projects/perses-plugins/alert-manager && npm run type-check` passes
- `cd projects/perses-plugins/alert-manager && npm run lint` passes
- Dev server starts: `percli plugin start projects/perses-plugins/alert-manager/`
- All module federation entry points resolve without errors
- Datasource editor renders and saves configuration
- Query editors render and build valid queries
- Alert table displays mock data with grouping and expand/collapse
- Silence table displays mock data with grouping
- Silence form opens, validates, and submits

---

### Phase 4: Register Alert Manager Plugin in Perses

**Dependency:** Phase 3 (plugin module must be built locally; use `percli plugin start` dev mode to load it — no published release needed) **Parallel
with:** None

#### Files Modified

| File                                | Change                                        |
| ----------------------------------- | --------------------------------------------- |
| `perses/scripts/plugin/plugin.yaml` | Add `AlertManager` entry with version `0.1.0` |

#### Details

Add to `scripts/plugin/plugin.yaml`:

```yaml
- name: "AlertManager"
  version: "0.1.0"
```

This entry is only needed for production. During local development, the plugin is loaded via dev mode instead:

1. Set `plugin.enable_dev: true` in Perses config
2. Run `percli plugin start projects/perses-plugins/alert-manager/` to start the plugin dev server
3. The backend proxies to the dev server — no tarball or GitHub release needed

The `plugin.yaml` change is committed on the branch but only takes effect after the plugin module is released to GitHub. This branch is the last to be
created and the last to be merged.

#### Phase 4 Verification

- Perses backend starts without errors
- `GET /api/v1/plugins` includes `AlertManager` module with all 7 plugins listed
- Plugin assets served at `/api/v1/plugins/AlertManager/`
- Navigate to Explore page: Alert Manager explorers appear in the plugin list
- Create a dashboard panel: Alert Table and Silence Table appear as panel type options
- Create a datasource: Alert Manager Datasource appears as datasource type option

---

## Branch & Local Linking Strategy

All code is developed on feature branches first, linked locally for integration testing. PRs are **not** created until all branches are complete and
verified end-to-end.

### Branch creation order (sequential)

| Step | Repository     | Branch                           | Description                                                                                                |
| ---- | -------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| 1    | perses/spec    | `feat/alertmanager-query-types`  | Add AlertsQuery and SilencesQuery types (Go + CUE + TypeScript)                                            |
| 2    | perses/shared  | `feat/alertmanager-plugin-types` | Add AlertsQuery/SilencesQuery plugin types to plugin-system; Add HierarchicalTable component to components |
| 3    | perses/plugins | `feat/alert-manager-plugin`      | New alert-manager plugin module with datasource, panels, queries, explore plugins                          |
| 4    | perses/perses  | `feat/alertmanager-registration` | Register AlertManager plugin in plugin.yaml                                                                |

### Local linking workflow

Dependencies between repos are resolved locally using `link-with-perses.sh` and `npm link`, never via published snapshots or waiting for upstream
merges.

**After Phase 1 (perses-spec branch ready):**

```bash
cd projects/perses-spec/ts && npm run build && npm link
cd projects/perses-shared && npm link @perses-dev/spec
```

**After Phase 2 (perses-shared branch ready):**

```bash
cd projects/perses-shared && npm run build
cd projects/perses-shared && ./scripts/link-with-perses/link-with-perses.sh link --plugins
```

This links `@perses-dev/components`, `@perses-dev/plugin-system`, `@perses-dev/explore`, and `@perses-dev/dashboards` into the perses-plugins
workspace so the alert-manager module can import the new types and components directly from the local build.

**After Phase 3 (perses-plugins branch ready):**

```bash
# Use dev mode — no release tarball needed
cd projects/perses && ./scripts/api_backend_dev.sh  # start backend with enable_dev: true
percli plugin start projects/perses-plugins/alert-manager/  # start plugin dev server
```

**Cleanup before PRs:**

```bash
cd projects/perses-shared && ./scripts/link-with-perses/link-with-perses.sh unlink --plugins
cd projects/perses-shared && npm install  # restore published dependencies
cd projects/perses-plugins && npm install  # restore published dependencies
```

### PR creation (deferred)

Once all four branches are complete and verified locally:

1. Create PRs in dependency order: `perses/spec` → `perses/shared` → `perses/plugins` → `perses/perses`
2. Merge sequentially — each PR targets `main` and must merge before the next can pass CI (since CI resolves published packages, not local links)
3. Between merges, the downstream repo's branch must be rebased to pick up the newly published package versions

## Verification

End-to-end verification mapped to the spec's acceptance criteria:

- [ ] **A new plugin module called `alert-manager` is created in the perses-plugins repository** - Verify `perses-plugins/alert-manager/` exists with
      correct package.json, builds successfully, and is loadable by Perses backend
- [ ] **The datasource plugin supports querying for alerts and silences** - Configure an Alert Manager datasource pointing to a test instance, create
      AlertsQuery and SilencesQuery, verify data returns
- [ ] **Alert table visualizes alerts in a hierarchical format with grouping and filtering** - Create a dashboard panel with AlertTable, verify
      grouping by alertname/cluster/severity works, expand/collapse groups, search/filter alerts
- [ ] **Silence table visualizes silences in a hierarchical format with grouping and filtering** - Create a dashboard panel with SilenceTable, verify
      grouping by status works, search/filter silences
- [ ] **Multi-datasource support** - Configure two Alert Manager datasources (simulating multi-cluster), add two queries to a single panel, verify
      alerts from both are merged and distinguishable
- [ ] **Alerts explore plugin supports querying alerts** - Navigate to Explore, select Alert Manager Alerts Explorer, build a query with filters,
      verify results display in the alert table
- [ ] **Silences explore plugin supports managing silences** - Navigate to Explore, select Alert Manager Silences Explorer, create a new silence with
      matchers, verify it appears in the silence table, edit the silence, expire the silence
- [ ] **Alert management is NOT included** - Verify no Prometheus rule editing or alert rule management features are present in the plugin

## Risks

| Risk                                                                                                                           | Impact                                                                            | Mitigation                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New query types (`AlertsQuery`, `SilencesQuery`) require changes across 3 repos in sequence, creating a long dependency chain  | Branch work is sequential; a mistake in Phase 1 types propagates to later phases  | Verify each phase's build and type-check before moving to the next; local linking catches type errors immediately                                          |
| `DataQueriesProvider` needs new query kind handlers for `AlertsQuery` and `SilencesQuery`                                      | Panels won't receive alert/silence data until the provider dispatches these kinds | Straightforward addition in `DataQueriesProvider.tsx` — the provider already supports pluggable query types, just add the two new kinds                    |
| Alert Manager v2 API may have different response formats across versions (e.g., AM 0.25 vs 0.28)                               | Client breaks with certain AM versions                                            | Pin to v2 API, add defensive parsing with fallbacks for optional fields, test against multiple AM versions                                                 |
| Silence create/edit requires write access through Perses proxy, which may be blocked by `allowedEndpoints` config              | Users can view but not manage silences                                            | Document required `allowedEndpoints` patterns for write operations (`POST /api/v2/silences`, `DELETE /api/v2/silence/{id}`)                                |
| HierarchicalTable component in perses-shared adds surface area to the shared library that must be maintained                   | Maintenance burden on perses-shared                                               | Keep the component minimal and generic; alert/silence-specific logic stays in the plugin                                                                   |
| Multi-cluster aggregation (merging alerts from N datasources) may produce duplicates when fingerprints diverge across clusters | Users see duplicate alerts or incorrect counts                                    | Configurable `deduplication` option: default `fingerprint` mode for identical rule sets, `labels` mode for heterogeneous clusters or custom label property |

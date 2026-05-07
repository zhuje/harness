# Plan: Add Variable Plugins to the Loki Perses Plugin

## Problem

The Loki plugin module in perses-plugins only supports datasource and query plugins. Users cannot use Loki-backed label or query results as dashboard
variable values. The Prometheus plugin already supports three variable types (LabelNames, LabelValues, PromQL) — this task mirrors that pattern for
Loki so that dashboards can use Loki queries as variable sources.

## Current State

| Component                   | File / Location                         | Current Behavior                                                                                                                                            |
| --------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Loki plugin registration    | `loki/package.json:50-79`               | Registers 3 plugins: LokiDatasource, LokiTimeSeriesQuery, LokiLogQuery. No variable plugins.                                                                |
| Loki client interface       | `loki/src/model/loki-client.ts:55-77`   | `LokiClient` interface has `labels()`, `labelValues()`, `query()` methods but `labels()` and `labelValues()` don't accept a matcher/query filter parameter. |
| Loki client `labels()`      | `loki/src/model/loki-client.ts:151-168` | Calls `/loki/api/v1/labels` with only `start`/`end` params. No stream selector filter.                                                                      |
| Loki client `labelValues()` | `loki/src/model/loki-client.ts:170-188` | Calls `/loki/api/v1/label/{name}/values` with only `start`/`end` params. No stream selector filter.                                                         |
| Loki datasource selectors   | `loki/src/model/loki-selectors.ts`      | Defines `LOKI_DATASOURCE_KIND`, `DEFAULT_LOKI`, `LokiDatasourceSelector`. Ready to use.                                                                     |
| Loki response types         | `loki/src/model/loki-client-types.ts`   | `LokiLabelsResponse`, `LokiLabelValuesResponse` return `{ data: string[] }`. `LokiQueryResponse` returns vector or stream results.                          |
| LogQL editor component      | `loki/src/components/logql-editor.tsx`  | CodeMirror-based editor with LogQL syntax highlighting. Reusable for LogQL variable editor.                                                                 |
| Loki exports                | `loki/src/index.ts:14-18`               | Exports `getPluginModule`, `model`, `queries`, `datasources`. No `variables` export.                                                                        |
| Prometheus variable pattern | `prometheus/src/plugins/`               | Three variable plugins with types, editors, CUE schemas, and test fixtures. This is the pattern to mirror.                                                  |

## Changes

### Phase 1: Update Loki Client to Support Matchers

**Dependency:** None **Parallel with:** Phase 2 (CUE schemas — different files)

The Loki API supports an optional `query` parameter on `/loki/api/v1/labels` and `/loki/api/v1/label/{name}/values` that acts as a stream selector
filter (equivalent to Prometheus's `match[]`). The current client doesn't pass this parameter. Update the client interface and implementation to
support it.

#### Files Modified

| File                            | Change                                                                                                                                                |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loki/src/model/loki-client.ts` | Add optional `query` parameter to `labels()` and `labelValues()` in both the interface and implementation functions. Add `getLokiTimeRange()` helper. |

#### Details

**Update `LokiClient` interface** (line 55-77):

```typescript
labels: (start?: string, end?: string, query?: string, headers?: LokiRequestHeaders) => Promise<LokiLabelsResponse>;
labelValues: (
  label: string,
  start?: string,
  end?: string,
  query?: string,
  headers?: LokiRequestHeaders
) => Promise<LokiLabelValuesResponse>;
```

**Update `labels()` function** (line 151-168) — add `query` parameter:

```typescript
export async function labels(
  start: string | undefined,
  end: string | undefined,
  query: string | undefined,
  options: LokiApiOptions
): Promise<LokiLabelsResponse> {
  const url = buildUrl('/loki/api/v1/labels', options.datasourceUrl);
  if (start) url.searchParams.append('start', start);
  if (end) url.searchParams.append('end', end);
  if (query) url.searchParams.append('query', query);
  // ... rest unchanged
}
```

**Update `labelValues()` function** (line 170-188) — add `query` parameter:

```typescript
export async function labelValues(
  label: string,
  start: string | undefined,
  end: string | undefined,
  query: string | undefined,
  options: LokiApiOptions
): Promise<LokiLabelValuesResponse> {
  const url = buildUrl(`/loki/api/v1/label/${label}/values`, options.datasourceUrl);
  if (start) url.searchParams.append('start', start);
  if (end) url.searchParams.append('end', end);
  if (query) url.searchParams.append('query', query);
  // ... rest unchanged
}
```

**Update `createClient` in `LokiDatasource.tsx`** (line 46-49) — pass through the new `query` parameter:

```typescript
labels: (start, end, query, headers) => labels(start, end, query, { datasourceUrl, headers: headers ?? specHeaders }),
labelValues: (label, start, end, query, headers) =>
  labelValues(label, start, end, query, { datasourceUrl, headers: headers ?? specHeaders }),
```

**Add `getLokiTimeRange()` helper** at the end of `loki-client.ts`:

```typescript
export function getLokiTimeRange(timeRange: AbsoluteTimeRange): { start: string; end: string } {
  return {
    start: toUnixSeconds(timeRange.start),
    end: toUnixSeconds(timeRange.end),
  };
}
```

**Update callers:** Check if `labels()` / `labelValues()` are called elsewhere in the Loki plugin (e.g., `complete.ts` for autocomplete). Add
`undefined` for the new `query` parameter at existing call sites.

#### Phase 1 Verification

- `cd projects/perses-plugins/loki && npm run type-check` passes
- `cd projects/perses-plugins/loki && npm test` passes

---

### Phase 2: Create CUE Schemas for Loki Variable Types

**Dependency:** None **Parallel with:** Phase 1 (different file tree)

Create CUE schema definitions for the three Loki variable types, following the same structure as Prometheus schemas. Also create validation test
fixtures.

#### Files Modified

| File                                                                          | Change                                           |
| ----------------------------------------------------------------------------- | ------------------------------------------------ |
| `loki/schemas/variables/loki-label-values/loki-label-values.cue`              | New file: CUE schema for LokiLabelValuesVariable |
| `loki/schemas/variables/loki-label-values/tests/valid/loki-label-values.json` | New file: valid test fixture                     |
| `loki/schemas/variables/loki-label-names/loki-label-names.cue`                | New file: CUE schema for LokiLabelNamesVariable  |
| `loki/schemas/variables/loki-label-names/tests/valid/loki-label-names.json`   | New file: valid test fixture                     |
| `loki/schemas/variables/loki-logql/loki-logql.cue`                            | New file: CUE schema for LokiLogQLVariable       |
| `loki/schemas/variables/loki-logql/tests/valid/loki-logql.json`               | New file: valid test fixture                     |
| `loki/schemas/variables/loki-logql/tests/invalid/no-label.json`               | New file: invalid test fixture                   |

#### Details

**`loki-label-values.cue`:**

```cue
package model

import (
  "strings"
  ds "github.com/perses/plugins/loki/schemas/datasources:model"
)

kind: "LokiLabelValuesVariable"
spec: close({
  ds.#selector
  labelName: strings.MinRunes(1)
  matchers?: [...string]
})
```

**`loki-label-names.cue`:**

```cue
package model

import (
  ds "github.com/perses/plugins/loki/schemas/datasources:model"
)

kind: "LokiLabelNamesVariable"
spec: close({
  ds.#selector
  matchers?: [...string]
})
```

**`loki-logql.cue`:**

```cue
package model

import (
  "strings"
  ds "github.com/perses/plugins/loki/schemas/datasources:model"
)

kind: "LokiLogQLVariable"
spec: close({
  ds.#selector
  expr:      strings.MinRunes(1)
  labelName: strings.MinRunes(1)
})
```

**Test fixtures:**

`loki-label-values/tests/valid/loki-label-values.json`:

```json
{
  "kind": "LokiLabelValuesVariable",
  "spec": {
    "labelName": "job",
    "matchers": ["{job=\"myapp\"}"]
  }
}
```

`loki-label-names/tests/valid/loki-label-names.json`:

```json
{
  "kind": "LokiLabelNamesVariable",
  "spec": {
    "matchers": ["{job=\"myapp\"}"]
  }
}
```

`loki-logql/tests/valid/loki-logql.json`:

```json
{
  "kind": "LokiLogQLVariable",
  "spec": {
    "expr": "count_over_time({job=\"myapp\"}[1h])",
    "labelName": "job"
  }
}
```

`loki-logql/tests/invalid/no-label.json`:

```json
{
  "kind": "LokiLogQLVariable",
  "spec": {
    "expr": "count_over_time({job=\"myapp\"}[1h])",
    "labelName": ""
  }
}
```

#### Phase 2 Verification

- CUE validation passes for valid fixtures, fails for invalid fixtures (if a CUE validation tool is configured)
- Schema directory structure matches the Prometheus pattern

---

### Phase 3: Implement Variable Plugin Types, Runtime Logic, and Editor UI

**Dependency:** Phase 1 (needs updated LokiClient interface) **Parallel with:** None

Create the three Loki variable plugins with types, runtime resolution logic, and editor UI components. This follows the exact structure of the
Prometheus variable plugins.

#### Files Modified

| File                                             | Change                                                                                                                                                |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `loki/src/variables/types.ts`                    | New file: TypeScript interfaces for all three variable options types                                                                                  |
| `loki/src/variables/loki-variables.tsx`          | New file: Editor components for all three variable types, plus shared helpers (`stringArrayToVariableOptions`, `capturingVector`, `capturingStreams`) |
| `loki/src/variables/MatcherEditor.tsx`           | New file: Matcher editor component for stream selector filters (same pattern as Prometheus)                                                           |
| `loki/src/variables/LokiLabelValuesVariable.tsx` | New file: LabelValues variable plugin definition                                                                                                      |
| `loki/src/variables/LokiLabelNamesVariable.tsx`  | New file: LabelNames variable plugin definition                                                                                                       |
| `loki/src/variables/LokiLogQLVariable.tsx`       | New file: LogQL variable plugin definition                                                                                                            |
| `loki/src/variables/index.ts`                    | New file: barrel export for all variable plugins                                                                                                      |
| `loki/src/index.ts`                              | Add `export * from './variables'`                                                                                                                     |
| `loki/package.json`                              | Register three new Variable plugins in the `perses.plugins` array                                                                                     |

#### Details

##### `loki/src/variables/types.ts`

```typescript
import { DatasourceSelectValue } from '@perses-dev/plugin-system';
import { LokiDatasourceSelector } from '../model';

export interface LokiVariableOptionsBase {
  datasource?: DatasourceSelectValue<LokiDatasourceSelector>;
}

export type LokiLabelNamesVariableOptions = LokiVariableOptionsBase & {
  matchers?: string[];
};

export type LokiLabelValuesVariableOptions = LokiVariableOptionsBase & {
  labelName: string;
  matchers?: string[];
};

export type LokiLogQLVariableOptions = LokiVariableOptionsBase & {
  expr: string;
  labelName: string;
};
```

##### `loki/src/variables/LokiLabelValuesVariable.tsx`

Mirrors `PrometheusLabelValuesVariable.tsx`:

1. Resolves the datasource selector via `datasourceSelectValueToSelector()` with `LOKI_DATASOURCE_KIND`
2. Gets the `LokiClient` via `ctx.datasourceStore.getDatasourceClient()`
3. Replaces variables in `labelName` and `matchers`
4. Converts matchers to a stream selector query string (join matchers or use the first one as the `query` parameter)
5. Calls `client.labelValues(labelName, start, end, query)` with time range from `getLokiTimeRange(ctx.timeRange)`
6. Converts `response.data` strings to `VariableOption[]` via `stringArrayToVariableOptions()`

**Matchers handling:** Unlike Prometheus which has `match[]` (array), Loki uses a single `query` parameter (a stream selector like `{job="myapp"}`).
The matchers array in the UI maps to this: if multiple matchers are provided, they are combined. Each matcher is a stream selector expression, and we
pass the first one as the `query` parameter (matching the UX pattern from Prometheus where each matcher is a separate selector).

##### `loki/src/variables/LokiLabelNamesVariable.tsx`

Same pattern as LabelValues but without the `labelName` field. Calls `client.labels(start, end, query)`.

##### `loki/src/variables/LokiLogQLVariable.tsx`

Mirrors `PrometheusPromQLVariable.tsx`:

1. Resolves datasource, gets `LokiClient`
2. Replaces variables in `expr` and `labelName`
3. Calls `client.query({ query: expr })` for an instant query
4. Processes the response:
   - For `vector` results: extracts `sample.metric[labelName]` from each `LokiVectorResult` (same as Prometheus)
   - For `streams` results: extracts `stream[labelName]` from each `LokiStreamResult` (unique to Loki — stream labels serve the same role as metric
     labels)
5. Returns unique values as `VariableOption[]`

The `capturingVector()` helper works identically to Prometheus's. A new `capturingStreams()` helper handles the Loki-specific stream result type.

##### `loki/src/variables/loki-variables.tsx`

Contains editor components:

**`LokiLabelValuesVariableEditor`** — Form with:

- `DatasourceSelect` (datasourcePluginKind="LokiDatasource", label="Loki Datasource")
- `TextField` (label="Label Name", required)
- `MatcherEditor` (stream selector matchers, optional)

**`LokiLabelNamesVariableEditor`** — Form with:

- `DatasourceSelect`
- `MatcherEditor`

**`LokiLogQLVariableEditor`** — Form with:

- `DatasourceSelect`
- `LogQLEditor` (from `../components`, with completion config using datasource URL)
- `TextField` (label="Label Name", required)

**Shared helpers:**

- `stringArrayToVariableOptions()` — identical to Prometheus version
- `capturingVector()` — extracts `metric[labelName]` from Loki vector results
- `capturingStreams()` — extracts `stream[labelName]` from Loki stream results

##### `loki/src/variables/MatcherEditor.tsx`

Same component as `prometheus/src/plugins/MatcherEditor.tsx` — a dynamic list of TextFields for stream selectors with add/remove buttons. The label
text changes from "Series Selector" to "Stream Selector" to match Loki terminology.

##### `loki/src/variables/index.ts`

```typescript
export * from './loki-variables';
export * from './LokiLabelNamesVariable';
export * from './LokiLabelValuesVariable';
export * from './LokiLogQLVariable';
export * from './MatcherEditor';
export * from './types';
```

##### `loki/src/index.ts` update

Add:

```typescript
export * from './variables';
```

##### `loki/package.json` update

Add three entries to `perses.plugins` array:

```json
{
  "kind": "Variable",
  "spec": {
    "display": { "name": "Loki Label Values Variable" },
    "name": "LokiLabelValuesVariable"
  }
},
{
  "kind": "Variable",
  "spec": {
    "display": { "name": "Loki Label Names Variable" },
    "name": "LokiLabelNamesVariable"
  }
},
{
  "kind": "Variable",
  "spec": {
    "display": { "name": "Loki LogQL Variable" },
    "name": "LokiLogQLVariable"
  }
}
```

#### Phase 3 Verification

- `cd projects/perses-plugins/loki && npm run type-check` passes
- `cd projects/perses-plugins/loki && npm test` passes
- `cd projects/perses-plugins/loki && npm run build` succeeds
- All three variable plugins are exported from the module

---

## PR Strategy

| PR | Repository     | Branch                                   | Description                                                                                                                       | Dependencies |
| -- | -------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 1  | perses/plugins | `feat/loki-variable-plugins` from `main` | Add LokiLabelValuesVariable, LokiLabelNamesVariable, and LokiLogQLVariable plugins with runtime logic, editor UI, and CUE schemas | None         |

All changes fit in a single PR since they're in one repository and form a cohesive feature.

## Verification

- [ ] **LokiLabelValuesVariable plugin exists** — exported from `@perses-dev/loki-plugin`, registered in `package.json` with `kind: "Variable"`, has
      CUE schema, editor component, and runtime `getVariableOptions` that calls `/loki/api/v1/label/{name}/values`
- [ ] **LokiLabelNamesVariable plugin exists** — exported from `@perses-dev/loki-plugin`, registered in `package.json` with `kind: "Variable"`, has
      CUE schema, editor component, and runtime `getVariableOptions` that calls `/loki/api/v1/labels`
- [ ] **LokiLogQLVariable plugin exists** — exported from `@perses-dev/loki-plugin`, registered in `package.json` with `kind: "Variable"`, has CUE
      schema, editor component, and runtime `getVariableOptions` that calls `/loki/api/v1/query` and extracts label values from vector/stream results
- [ ] **Type check passes** — `npm run type-check` in the loki plugin directory
- [ ] **Tests pass** — `npm test` in the loki plugin directory
- [ ] **Build succeeds** — `npm run build` in the loki plugin directory
- [ ] **Matchers supported** — LabelValues and LabelNames variable plugins accept optional `matchers` (stream selectors) and pass them as the `query`
      parameter to the Loki API
- [ ] **Variable dependencies tracked** — all three plugins implement `dependsOn` to declare variable references in their spec fields

## Risks

| Risk                                                                          | Impact                                                                                                                                                            | Mitigation                                                                                                                                                                    |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Loki API `query` param on labels endpoints not supported by all Loki versions | Matchers silently ignored on older Loki instances; variable still works but returns unfiltered results                                                            | The `query` param is optional — the feature degrades gracefully. Document minimum Loki version in the PR.                                                                     |
| LogQL editor component lacks autocomplete for variable context                | Users don't get syntax hints when writing LogQL expressions for variables                                                                                         | The existing `LogQLEditor` with `completionConfig` provides basic LogQL completion. Full variable-aware completion is a future enhancement.                                   |
| `LokiClient` interface change breaks external consumers                       | Callers of `labels()` / `labelValues()` that don't pass the new `query` param get TypeScript errors                                                               | The new `query` parameter is optional (`query?: string`), so existing callers continue to work without changes. Update internal call sites.                                   |
| Matchers UX differs from Prometheus                                           | Prometheus uses `match[]` (multiple matchers), Loki uses a single `query` (stream selector). The UI shows multiple matcher fields but they're joined differently. | Each matcher field represents a stream selector. Use the same multi-field UI pattern as Prometheus for consistency. Combine multiple matchers appropriately for the Loki API. |

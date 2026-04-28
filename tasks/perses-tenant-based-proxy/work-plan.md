# Work Plan: Variable Interpolation for Datasource Proxy Headers and Query Parameters

## Problem

The Perses datasource proxy uses static headers and query parameters defined at datasource configuration time. In multi-tenant observability platforms
(e.g., OpenShift with Thanos), dashboards need to send dynamic tenant headers (`X-Scope-OrgID`) and query parameters based on dashboard variable
values. Currently, there is no mechanism for dashboard variables to influence proxy request headers or query parameters — variables are only
interpolated in PromQL queries and series name formats.

**Upstream issue:** [perses/perses#3940 — Include custom parameters when proxying requests to datasources queries](https://github.com/perses/perses/issues/3940)

## Current State

| Component         | File                                                                       | Behavior                                               |
| ----------------- | -------------------------------------------------------------------------- | ------------------------------------------------------ |
| Prometheus client | `perses-plugins/prometheus/src/model/prometheus-client.ts`                 | `queryParams` baked in at client creation (line 86-97) |
| Prometheus plugin | `perses-plugins/prometheus/src/plugins/prometheus-datasource.tsx`          | `specHeaders` static from `proxy.spec.headers` (ln 43) |
| Query execution   | `perses-plugins/prometheus/src/plugins/.../get-time-series-data.ts`        | Interpolates PromQL query only, not headers/params     |
| Variable system   | `perses-shared/components/src/utils/variable-interpolation.ts`             | `replaceVariables()` supports `$var` and `${var:fmt}`  |
| Backend proxy     | `perses/internal/api/impl/proxy/proxy.go`                                  | Applies headers verbatim from config (line 342-357)    |
| monitoring-plugin | `monitoring-plugin/web/src/components/dashboards/perses/datasource-api.ts` | No tenant header injection                             |

## Changes

### Phase 1: Extend Prometheus Client to Support Per-Call Query Params

**Dependency:** None

#### Files Modified

| File                                                       | Change                                                             |
| ---------------------------------------------------------- | ------------------------------------------------------------------ |
| `perses-plugins/prometheus/src/model/prometheus-client.ts` | Change `queryParams` type to support arrays, add per-call override |
| `perses-plugins/prometheus/src/plugins/types.ts`           | Change `queryParams` type to `Record<string, string \| string[]>`  |

#### Details

##### Query param sources and merge precedence

With our changes, three sources of query params can coexist:

| Source                     | Set at          | Example keys                                        | Priority |
| -------------------------- | --------------- | --------------------------------------------------- | -------- |
| API request params         | each call       | `query`, `start`, `end`, `step`, `match[]`, `limit` | highest  |
| Interpolated queryParams   | each call (new) | user-defined with `$var` references                 | middle   |
| Static default queryParams | client creation | user-defined, fixed values                          | lowest   |

Precedence rule: **API request params must never be overwritten.** Interpolated per-call params override static defaults. Datasource-level params
(both static and interpolated) should only add new keys, never collide with Prometheus API params.

##### Current collision bug in `fetchWithGet`

The two fetch methods handle the merge differently:

- **`fetchWithPost`** (used by `instantQuery`, `rangeQuery`, `labelNames`, `series`, `parseQuery`): API params go in the POST body, datasource
  queryParams go in the URL query string. **No collision** — different locations.
- **`fetchWithGet`** (used by `labelValues`, `metricMetadata`): Both API params and datasource queryParams go in the same URL query string.
  `buildQueryString` receives API params as `initialParams`, then calls `urlParams.set(key, value)` for datasource params. **`.set()` overwrites
  existing keys**, so a datasource queryParam like `start` would silently replace the API's `start`. This is a pre-existing bug that our changes must
  not carry forward.

##### Change `queryParams` to support array values

Change `queryParams` from `Record<string, string>` to `Record<string, string | string[]>`:

```typescript
// In types.ts
export interface PrometheusDatasourceSpec {
  directUrl?: string;
  proxy?: HTTPProxy;
  scrapeInterval?: DurationString;
  queryParams?: Record<string, string | string[]>;
}
```

##### Fix `buildQueryString` to prevent collisions

Update `buildQueryString` in `prometheus-client.ts` to:

1. Handle array values via `urlParams.append`
2. Skip datasource queryParam keys that already exist in `initialParams` (API request params win)

```typescript
function buildQueryString(
  queryParams?: Record<string, string | string[]>,
  initialParams?: URLSearchParams
): string {
  const urlParams = initialParams || new URLSearchParams();
  if (queryParams) {
    Object.entries(queryParams).forEach(([key, value]) => {
      // Do not overwrite API request params that were set via initialParams
      if (initialParams?.has(key)) return;

      if (Array.isArray(value)) {
        value.forEach((v) => urlParams.append(key, v));
      } else {
        urlParams.set(key, value);
      }
    });
  }
  const queryString = urlParams.toString();
  return queryString !== '' ? `?${queryString}` : '';
}
```

##### Add per-call override

Currently, `queryParams` is captured at client creation and fixed for all requests. The `PrometheusClient` interface methods already accept optional
`headers` per call. Extend this pattern to also accept optional `queryParams` per call, or accept a combined options object that includes both.

When both static (default) and per-call (interpolated) queryParams exist, merge them so per-call values override static defaults for the same key:

```typescript
function mergeQueryParams(
  defaults?: Record<string, string | string[]>,
  overrides?: Record<string, string | string[]>
): Record<string, string | string[]> | undefined {
  if (!defaults && !overrides) return undefined;
  return { ...defaults, ...overrides };
}
```

This merge happens inside the client methods before calling `fetchWithGet`/`fetchWithPost`, so `buildQueryString` receives a single merged queryParams
map.

### Phase 2: Add Variable Interpolation in Query Execution

**Dependency:** Phase 1

#### Files Modified

| File                                                                                         | Change                                                                       |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `perses-plugins/prometheus/src/plugins/prometheus-time-series-query/get-time-series-data.ts` | Interpolate headers and queryParams with `context.variableState`             |
| `perses-plugins/prometheus/src/plugins/PrometheusPromQLVariable.tsx`                         | Add `getDatasource` call, interpolate headers/queryParams for `instantQuery` |
| `perses-plugins/prometheus/src/plugins/PrometheusLabelNamesVariable.tsx`                     | Add `getDatasource` call, interpolate headers/queryParams for `labelNames`   |
| `perses-plugins/prometheus/src/plugins/PrometheusLabelValuesVariable.tsx`                    | Add `getDatasource` call, interpolate headers/queryParams for `labelValues`  |
| `perses-plugins/prometheus/src/plugins/prometheus-datasource.tsx`                            | Expose raw (non-interpolated) spec headers/queryParams on the client         |

#### Variable Interpolation and Format Specifiers

The existing `replaceVariables()` function in `@perses-dev/components` already supports multi-value variables and format specifiers via the
`${var:format}` syntax. The `InterpolationFormat` enum provides formats relevant to proxy configuration:

| Format                       | Input `["ns1","ns2"]` | Output       | Use case                              |
| ---------------------------- | --------------------- | ------------ | ------------------------------------- |
| `$namespace` (default)       | array                 | `(ns1\|ns2)` | Prometheus regex (default for arrays) |
| `${namespace:csv}`           | array                 | `ns1,ns2`    | Comma-separated header value          |
| `${namespace:pipe}`          | array                 | `ns1\|ns2`   | Pipe-separated header value           |
| `${namespace:percentencode}` | array                 | `ns1%2Cns2`  | URL-safe encoding                     |
| `$namespace` (default)       | single string         | `ns1`        | Single value, no formatting needed    |

For headers, `replaceVariables` always returns a single string — the format controls how array values are serialized into that string.

For query params, array expansion is handled separately: each element of a multi-value variable becomes a repeated query parameter (e.g.,
`namespace=ns1&namespace=ns2`). This is done by the `interpolateQueryParams` helper (see below), not by format specifiers.

#### Details — get-time-series-data.ts

After getting the datasource spec (line 61-66 in current code), extract headers and queryParams, interpolate them, and pass to client methods:

```typescript
import { replaceVariables } from '@perses-dev/plugin-system';

// After: const datasource = await context.datasourceStore.getDatasource(selectedDatasource);

// Interpolate headers — replaceVariables handles both single and array values via format specifiers
const interpolatedHeaders = interpolateHeaders(
  datasource.plugin.spec.proxy?.spec?.headers ?? {},
  context.variableState
);

// Interpolate queryParams — expands array variable values into repeated params
const interpolatedQueryParams = interpolateQueryParams(
  datasource.plugin.spec.queryParams ?? {},
  context.variableState
);

// Pass to client methods (existing headers param, new queryParams param)
response = await client.rangeQuery(
  { query, start, end, step },
  interpolatedHeaders,
  abortSignal,
  interpolatedQueryParams
);
```

#### Details — Variable Plugin Files

The three variable plugins (`PrometheusLabelNamesVariable`, `PrometheusLabelValuesVariable`, `PrometheusPromQLVariable`) share the same gap: they call
`ctx.datasourceStore.getDatasourceClient(selector)` to get a client, but never call `ctx.datasourceStore.getDatasource(selector)` to get the spec.
Without the spec, they have no access to `proxy.spec.headers` or `queryParams` to interpolate.

Each plugin needs the same two additions:

1. Fetch the datasource spec alongside the client
2. Interpolate headers/queryParams and pass them to the client method call

##### PrometheusLabelNamesVariable.tsx (line 34-38)

Current code calls `client.labelNames(...)` without headers or queryParams:

```typescript
const client: PrometheusClient = await ctx.datasourceStore.getDatasourceClient(datasourceSelector);
const { data: options } = await client.labelNames({ 'match[]': match, ...timeRange });
```

Changed to:

```typescript
const [client, datasource] = await Promise.all([
  ctx.datasourceStore.getDatasourceClient<PrometheusClient>(datasourceSelector),
  ctx.datasourceStore.getDatasource(datasourceSelector),
]);
const headers = interpolateHeaders(datasource.plugin.spec.proxy?.spec?.headers ?? {}, ctx.variables);
const queryParams = interpolateQueryParams(datasource.plugin.spec.queryParams ?? {}, ctx.variables);
const { data: options } = await client.labelNames({ 'match[]': match, ...timeRange }, headers, undefined, queryParams);
```

##### PrometheusLabelValuesVariable.tsx (line 35-44)

Current code calls `client.labelValues(...)` without headers or queryParams:

```typescript
const client: PrometheusClient = await ctx.datasourceStore.getDatasourceClient(datasourceSelector);
const { data: options } = await client.labelValues({ labelName: ..., 'match[]': match, ...timeRange });
```

Changed to:

```typescript
const [client, datasource] = await Promise.all([
  ctx.datasourceStore.getDatasourceClient<PrometheusClient>(datasourceSelector),
  ctx.datasourceStore.getDatasource(datasourceSelector),
]);
const headers = interpolateHeaders(datasource.plugin.spec.proxy?.spec?.headers ?? {}, ctx.variables);
const queryParams = interpolateQueryParams(datasource.plugin.spec.queryParams ?? {}, ctx.variables);
const { data: options } = await client.labelValues(
  { labelName: replaceVariables(pluginDef.labelName, ctx.variables), 'match[]': match, ...timeRange },
  headers, undefined, queryParams
);
```

##### PrometheusPromQLVariable.tsx (line 39-43)

Current code calls `client.instantQuery(...)` without headers or queryParams:

```typescript
const client: PrometheusClient = await ctx.datasourceStore.getDatasourceClient(datasourceSelector);
const { data: options } = await client.instantQuery({ query: replaceVariables(spec.expr, ctx.variables) });
```

Changed to:

```typescript
const [client, datasource] = await Promise.all([
  ctx.datasourceStore.getDatasourceClient<PrometheusClient>(datasourceSelector),
  ctx.datasourceStore.getDatasource(datasourceSelector),
]);
const headers = interpolateHeaders(datasource.plugin.spec.proxy?.spec?.headers ?? {}, ctx.variables);
const queryParams = interpolateQueryParams(datasource.plugin.spec.queryParams ?? {}, ctx.variables);
const { data: options } = await client.instantQuery(
  { query: replaceVariables(spec.expr, ctx.variables) },
  headers, undefined, queryParams
);
```

Note: all three variable plugins use `ctx.variables` (type `VariableStateMap`) rather than `context.variableState` — same data, different context
object name. The `getTimeSeriesData` function uses `context.variableState` because it comes from `TimeSeriesQueryPlugin` context.

#### Details — prometheus-datasource.tsx createClient

Currently `createClient` bakes `specHeaders` into every method call. Instead, store the raw values so callers can override per-request:

```typescript
const createClient = (spec, options) => {
  const { directUrl, proxy, queryParams } = spec;
  const { proxyUrl } = options;
  const datasourceUrl = directUrl ?? proxyUrl;

  // Store raw (possibly containing $var references) values as defaults
  const defaultHeaders = proxy?.spec.headers;
  const defaultQueryParams = queryParams;

  return {
    options: { datasourceUrl, defaultHeaders, defaultQueryParams },
    // Per-call headers and queryParams override defaults
    rangeQuery: (params, headers, abortSignal, callQueryParams) =>
      rangeQuery(params, {
        datasourceUrl,
        headers: headers ?? defaultHeaders,
        abortSignal,
        queryParams: callQueryParams ?? defaultQueryParams,
      }),
    // ... same pattern for other methods
  };
};
```

#### Helper Functions

Create reusable helpers in a shared utility file within the prometheus plugin to avoid duplicating interpolation logic across query functions:

```typescript
import { replaceVariables, parseVariables, VariableStateMap } from '@perses-dev/plugin-system';

/**
 * Interpolate header values with variable state.
 * Multi-value variables are serialized using format specifiers (e.g., ${var:csv}).
 * Returns a flat Record<string, string> since HTTP headers are always single-valued strings.
 */
function interpolateHeaders(
  headers: Record<string, string>,
  variableState: VariableStateMap
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(headers)) {
    result[key] = replaceVariables(value, variableState);
  }
  return result;
}

/**
 * Interpolate query param values with variable state.
 * Supports both single and array values:
 * - Single string values: interpolated with replaceVariables (format specifiers apply).
 * - Array values: each element is interpolated separately, producing repeated query params.
 *
 * Example config:
 *   { "namespace": ["$ns1", "$ns2"], "cluster": "$cluster" }
 * With ns1="a", ns2="b", cluster="prod" produces:
 *   { "namespace": ["a", "b"], "cluster": "prod" }
 */
function interpolateQueryParams(
  queryParams: Record<string, string | string[]>,
  variableState: VariableStateMap
): Record<string, string | string[]> {
  const result: Record<string, string | string[]> = {};
  for (const [key, value] of Object.entries(queryParams)) {
    if (Array.isArray(value)) {
      result[key] = value.map((v) => replaceVariables(v, variableState));
    } else {
      result[key] = replaceVariables(value, variableState);
    }
  }
  return result;
}
```

### Phase 3: Extend queryParams Support to Other Plugins

**Dependency:** None (can be discussed upstream in parallel with Phase 1-2)

**Upstream issue:** [perses/perses#3940](https://github.com/perses/perses/issues/3940)

#### Context

Issue #3940 proposes two things:

1. Enable variable interpolation in the existing Prometheus `queryParams` field — **this is Phase 1-2, already implemented**
2. Replicate the `queryParams` + interpolation pattern to other datasource plugins (Loki, Tempo, ClickHouse, etc.)

The issue keeps `queryParams` at the **plugin spec level** (same level as `proxy`, not inside `proxy.spec`):

```json
{
  "plugin": {
    "kind": "PrometheusDatasource",
    "spec": {
      "proxy": { "kind": "HTTPProxy", "spec": { "url": "..." } },
      "queryParams": { "namespace": "${namespace:queryparam}" }
    }
  }
}
```

With `namespace` variable set to `["default", "other"]`, this produces:
`POST .../api/v1/query_range?namespace=default&namespace=other`

#### Two approaches for replication

##### Approach A: Per-plugin queryParams (aligned with issue #3940)

Each plugin adds its own `queryParams` field to its datasource spec, replicating the Prometheus pattern:

```typescript
// Each plugin adds this to their spec
export interface LokiDatasourceSpec {
  directUrl?: string;
  proxy?: HTTPProxy;
  queryParams?: Record<string, string | string[]>;  // NEW — same as Prometheus
}
```

Each plugin's query functions handle interpolation individually, using the same `interpolateQueryParams` helper
(which could be moved to `@perses-dev/plugin-system` for sharing).

| Pros | Cons |
| --- | --- |
| No shared model changes | Each plugin duplicates the field and wiring |
| No Go proxy handler changes | CUE schemas diverge across plugins |
| Simpler, fewer repos touched | No single place to configure queryParams |
| Aligned with upstream proposal | |

##### Approach B: Shared queryParams in HTTPProxySpec

Move `queryParams` into `HTTPProxySpec` (alongside `headers`). All plugins get it automatically.

```
HTTPProxySpec:
  url: string
  headers?: Record<string, string>
  queryParams?: Record<string, string | string[]>  ← NEW, shared
  allowedEndpoints?: [...]
  secret?: string
```

| Pros | Cons |
| --- | --- |
| Consistent with `headers` pattern | Requires Go, CUE, TS changes across 2+ repos |
| All plugins get it for free | Go proxy must handle queryParams server-side |
| Single configuration location | Interaction between server-side and client-side interpolated params needs dedup |
| | May not match upstream maintainers' direction |

#### Where the HTTPProxy model lives (for Approach B)

The `perses/spec` repo (`github.com/perses/spec`) does **not** contain HTTPProxy — it only has the outer wrapper types (`DatasourceSpec`,
`Plugin`, `Display`). The HTTPProxy model is split across:

| Layer | Repository | File |
| --- | --- | --- |
| Go struct | `perses/perses` | `pkg/model/api/v1/datasource/http/http.go` |
| Go proxy handler | `perses/perses` | `internal/api/impl/proxy/proxy.go` |
| CUE schema | `perses/perses-shared` | `cue/common/proxy/http.cue` |
| TypeScript types | `perses/perses` | `ui/core/src/model/http-proxy.ts` (via `@perses-dev/core`) |

#### Recommendation

**Start with Approach A** (aligned with issue #3940): keep `queryParams` at the plugin spec level, replicate to other plugins. This is simpler,
doesn't require upstream model changes, and matches the direction proposed in the issue. Phase 1-2 already implements this for Prometheus.

Approach B can be proposed as a follow-up if the community wants to consolidate — but the interpolation infrastructure built in Phase 1-2
(the `interpolateQueryParams` helper, the per-call override pattern in the client) works with either approach.

#### Shared helpers (done)

Generic helpers live in `@perses-dev/components` alongside other interpolation utilities (`variable-interpolation.ts`,
`data-field-interpolation.ts`, `selection-interpolation.ts`):

| File | Contents |
| --- | --- |
| `perses-shared/components/src/utils/request-interpolation.ts` | `interpolateHeaders`, `interpolateQueryParams`, `QueryParamValues` type |
| `perses-shared/components/src/utils/index.ts` | Barrel re-export |

Plugins import directly from `@perses-dev/components`. The Prometheus plugin's `interpolation.ts` keeps only the
Prometheus-specific `interpolateDatasourceProxyParams` and `resolvePrometheusDatasource`.

#### Remaining steps for replication (Approach A)

1. Add `queryParams?: Record<string, string | string[]>` to each plugin's datasource spec (Loki, Tempo, ClickHouse)
2. Each plugin's query functions import `interpolateHeaders`/`interpolateQueryParams` from `@perses-dev/plugin-system`
3. Update CUE schemas for each plugin to include `queryParams`

### Phase 4: Update Monitoring Plugin

**Dependency:** Phase 2 (upstream PR merged and released)

#### Files Modified

| File                                                                                    | Change                                                        |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `monitoring-plugin/web/package.json`                                                    | Update `@perses-dev/*` dependencies to versions with this fix |
| `monitoring-plugin/web/src/components/dashboards/perses/perses/datasource-cache-api.ts` | Add tenant headers to datasource configuration                |

#### Details

Once the upstream Perses changes are released, update the monitoring plugin to:

1. Bump `@perses-dev/plugin-system`, `@perses-dev/components`, and Prometheus plugin versions
2. Configure datasources with tenant header variables in the datasource spec:

```json
{
  "proxy": {
    "kind": "HTTPProxy",
    "spec": {
      "url": "https://thanos-querier.openshift-monitoring.svc:9091",
      "headers": {
        "X-Scope-OrgID": "${namespace:csv}"
      }
    }
  }
}
```

When `namespace = ["ns1", "ns2"]`, the header is sent as `X-Scope-OrgID: ns1,ns2`. For a single value `namespace = "ns1"`, it sends
`X-Scope-OrgID: ns1`. The format specifier (`:csv`, `:pipe`, etc.) controls how multi-value variables are serialized into the header string.

3. If custom query parameters are needed, add them to `queryParams`. Array values produce repeated query params:

```json
{
  "queryParams": {
    "namespace": ["$ns1", "$ns2"],
    "cluster": "$cluster"
  }
}
```

With `ns1 = "a"`, `ns2 = "b"`, `cluster = "prod"`, this produces the query string `?namespace=a&namespace=b&cluster=prod`.

For a simpler single-variable case with a multi-value variable, use a single value with a format specifier:

```json
{
  "queryParams": {
    "namespace": "${namespace:csv}"
  }
}
```

With `namespace = ["ns1", "ns2"]`, this produces `?namespace=ns1%2Cns2` (comma-separated, URL-encoded).

## PR Strategy

| PR # | Repository        | Branch | Description                                                               |
| ---- | ----------------- | ------ | ------------------------------------------------------------------------- |
| 1    | perses-plugins    | `main` | Support per-call queryParams and header/queryParam variable interpolation |
| 2    | perses-plugins    | `main` | Replicate queryParams + interpolation to Loki, Tempo, ClickHouse (Phase 3) |
| 3    | monitoring-plugin | `main` | Bump Perses deps, configure tenant headers                                |

## Verification

- `interpolateHeaders` unit test: verify `$var` and `${var:format}` patterns are replaced in header values
- `interpolateQueryParams` unit test: verify single strings, arrays, and format specifiers are handled correctly
- Multi-value variable tests:
  - Header with `${var:csv}` where `var = ["a", "b"]` produces `"a,b"`
  - Header with `${var:pipe}` where `var = ["a", "b"]` produces `"a|b"`
  - Query param array `["$v1", "$v2"]` where `v1 = "a"`, `v2 = "b"` produces `?key=a&key=b`
  - Query param with `${var:csv}` where `var = ["a", "b"]` produces `?key=a%2Cb`
- `buildQueryString` collision tests:
  - `labelValues` with datasource queryParam `start` must NOT overwrite the API's `start` param
  - `labelValues` with datasource queryParam `namespace` (non-colliding) is correctly appended
  - Verify `initialParams?.has(key)` guard prevents overwrites for all GET-based API calls
- `mergeQueryParams` tests:
  - Per-call interpolated params override static defaults for the same key
  - Keys present only in defaults are preserved
  - Keys present only in overrides are added
- `get-time-series-data` unit tests: verify interpolated headers/queryParams are passed to client methods
- Manual test: create a Perses dashboard with a list variable (multi-select) and a datasource with `${var:csv}` in headers, verify browser network tab
  shows correctly formatted header values
- monitoring-plugin integration test: deploy on OpenShift, verify tenant header is sent to Thanos with the correct namespace value

## Risks

- **Client caching**: The Prometheus client is cached via react-query. Since we interpolate at query execution time (not client creation), this is not
  affected. The client stores raw/default values, and interpolated values are passed per-call.
- **Variable timing**: Variables may not be resolved when the first query fires. The existing variable system handles this via loading states and
  re-queries — the same behavior applies to headers/queryParams.
- **Pre-existing collision bug**: `buildQueryString` currently uses `.set()` which allows datasource queryParams to overwrite API request params in
  `fetchWithGet` calls (`labelValues`, `metricMetadata`). Our fix (skip keys present in `initialParams`) changes the existing merge behavior. While
  the old behavior was unsafe, any existing datasource configs that rely on overwriting API params would break. This is unlikely since overwriting
  `start`, `end`, or `match[]` would produce broken queries, but should be noted in the PR description.
- **Upstream acceptance**: The interpolation approach needs to align with Perses upstream maintainers' vision. The design follows existing patterns
  (PromQL query interpolation) to minimize friction.

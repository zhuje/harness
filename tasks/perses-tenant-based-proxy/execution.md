# Execution: Variable Interpolation for Datasource Proxy Headers and Query Parameters

## Phase 1: Extend Prometheus Client (perses-plugins)

Depends on: nothing

- [x] Create feature branch `feat/proxy-variable-interpolation` in perses-plugins
- [x] Update `types.ts`: change `queryParams` type to `Record<string, string | string[]>`
- [x] Update `prometheus-client.ts`: fix `buildQueryString` to handle arrays and prevent collisions with API params
- [x] Update `prometheus-client.ts`: add `mergeQueryParams` helper
- [x] Update `prometheus-client.ts`: update `QueryOptions.queryParams` type to `Record<string, string | string[]>`
- [x] Update `PrometheusClient` interface: add optional `queryParams` parameter to all methods alongside existing `headers`
- [x] Update `prometheus-datasource.tsx` `createClient`: wire per-call queryParams and headers through to client methods

## Phase 2: Add Variable Interpolation in Query Execution (perses-plugins)

Depends on: Phase 1

### 2a. Create helper functions

- [x] Create `interpolateHeaders` and `interpolateQueryParams` helpers in `interpolation.ts`

### 2b. Update query and variable files (can parallelize)

- [x] Update `get-time-series-data.ts`: add `getDatasource` call, interpolate headers/queryParams, pass to client
- [x] Update `PrometheusLabelNamesVariable.tsx`: add `getDatasource` call, interpolate headers/queryParams for `labelNames`
- [x] Update `PrometheusLabelValuesVariable.tsx`: add `getDatasource` call, interpolate headers/queryParams for `labelValues`
- [x] Update `PrometheusPromQLVariable.tsx`: add `getDatasource` call, interpolate headers/queryParams for `instantQuery`

### 2c. Verify

- [x] TypeScript compilation passes (`tsc --noEmit`)
- [x] Existing tests pass (pre-existing jest config issue — tests fail on main too, not caused by our changes)
- [x] Fix `PrometheusDatasourceEditor.tsx`: handle widened `queryParams` type in editor state initialization
- [ ] Commit changes

## Phase 3: Replicate queryParams to Other Plugins (perses-plugins)

Depends on: Phase 1-2 (Prometheus implementation as reference)

Upstream issue: [perses/perses#3940](https://github.com/perses/perses/issues/3940)

Approach: per-plugin queryParams (aligned with issue #3940) — each plugin adds its own `queryParams` field

### 3a. Share interpolation helpers

- [x] Create `interpolateHeaders`/`interpolateQueryParams` in `perses-shared/components/src/utils/request-interpolation.ts`
- [x] Add barrel export in `perses-shared/components/src/utils/index.ts`
- [x] Update Prometheus `interpolation.ts` to import helpers from `@perses-dev/components`

### 3b. Add queryParams to other plugins (can parallelize)

- [ ] Loki: add `queryParams` to `LokiDatasourceSpec`, wire interpolation in query functions
- [ ] Tempo: add `queryParams` to `TempoDatasourceSpec`, wire interpolation in query functions
- [ ] ClickHouse: add `queryParams` to `ClickHouseDatasourceSpec`, wire interpolation in query functions
- [ ] Update CUE schemas for each plugin

### 3c. Verify

- [ ] TypeScript compilation passes for all plugins
- [ ] Existing tests pass

## Phase 4: Update Monitoring Plugin

Depends on: Phase 2 (upstream PR merged and released)

- [ ] Bump `@perses-dev/*` dependencies
- [ ] Configure datasources with tenant headers (`X-Scope-OrgID: ${namespace:csv}`)
- [ ] Verify compilation and tests pass

# Plan: Refactor Alert-Related Repos to Use New Generic Types

## Problem

The prior task (`refactor-alert-manager-data-type`) refactored the TypeScript types in `perses-spec` to be provider-agnostic. The `Alert` and
`Silence` interfaces were redesigned with generic state models, removing AlertManager-specific coupling. However, the downstream repos
(`perses-shared`, `perses-plugins`, `perses`) still use the old AlertManager-coupled types. This task propagates the new generic types into those
repos, adding explicit mapping functions in the AlertManager plugin to convert between the AM API format and the generic model.

### Key type changes in perses-spec (already done)

**Alert:** `status: { state: 'active'|'suppressed'|'unprocessed', silencedBy, inhibitedBy, mutedBy }` → `state: AlertState`
(`'inactive'|'pending'|'firing'|'resolved'`) + `suppressed?: boolean` + `suppressedBy?: SuppressionRule[]`. Added `id`, `name`, `severity?`,
`sourceURL?`, `acknowledged?`. Changed `receivers` from `Array<{ name: string }>` to `string[]`. Removed `fingerprint`, `generatorURL`, `AlertStatus`,
`Receiver`.

**Silence:** `status: { state }` → `state: SilenceState` (inlined). Removed `annotations`. Renamed `Matcher` → `SilenceMatcher`. Made `isRegex`,
`isEqual`, `comment`, `updatedAt` optional.

## Current State

| Component                  | File / Location                                                                                           | Current Behavior                                                                                                                                    |
| -------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Spec alert types           | `projects/perses-spec/ts/src/dashboard/query-type/alerts-data.ts`                                         | Generic `Alert` with `id`, `name`, `state: AlertState`, `suppressedBy?: SuppressionRule[]` — already refactored                                     |
| Spec silence types         | `projects/perses-spec/ts/src/dashboard/query-type/silences-data.ts`                                       | Generic `Silence` with `state: SilenceState`, `matchers: SilenceMatcher[]` — already refactored                                                     |
| Shared mock data           | `projects/perses-shared/plugin-system/src/test/mock-data.ts:120-166`                                      | Uses old AM-coupled format: `status: { state, silencedBy, inhibitedBy, mutedBy }`, `receivers: [{ name }]`, `fingerprint`, `annotations` on Silence |
| Plugin alert transform     | `projects/perses-plugins/alertmanager/src/plugins/alertmanager-alerts-query/get-alerts-data.ts:22-39`     | `transformAlert` copies AM fields directly without mapping states or field names                                                                    |
| Plugin silence transform   | `projects/perses-plugins/alertmanager/src/plugins/alertmanager-silences-query/get-silences-data.ts:21-38` | `transformSilence` copies `status: { state }` wrapper and adds empty `annotations`                                                                  |
| Plugin StatusBadge         | `projects/perses-plugins/alertmanager/src/components/StatusBadge.tsx:27-31`                               | Maps AM states `active`/`suppressed`/`unprocessed` to display labels                                                                                |
| Plugin alert table model   | `projects/perses-plugins/alertmanager/src/plugins/alert-table/alert-table-model.ts:95,155-162`            | Uses `alert.fingerprint` for dedup, `alert.status.state` for group summary with AM state values                                                     |
| Plugin AlertTablePanel     | `projects/perses-plugins/alertmanager/src/plugins/alert-table/AlertTablePanel.tsx:151,198,306`            | Uses `alert.status.state`, `alert.status?.silencedBy`, `alert.fingerprint`                                                                          |
| Plugin SilenceTablePanel   | `projects/perses-plugins/alertmanager/src/plugins/silence-table/SilenceTablePanel.tsx:57,97,197`          | Uses `silence.status?.state`                                                                                                                        |
| Plugin silence table model | `projects/perses-plugins/alertmanager/src/plugins/silence-table/silence-table-model.ts:74`                | Uses `silence.status?.state`                                                                                                                        |
| Plugin MatchersList        | `projects/perses-plugins/alertmanager/src/components/MatchersList.tsx:15`                                 | Imports `Matcher` from `@perses-dev/spec` (renamed to `SilenceMatcher`)                                                                             |
| Plugin AM API types        | `projects/perses-plugins/alertmanager/src/model/api-types.ts`                                             | `GettableAlert`, `GettableSilence`, `Matcher` — AM v2 API types, stays as-is                                                                        |

## Changes

### Phase 1: perses-shared — Update mock data to match new spec types

**Dependency:** None **Parallel with:** Phase 2 (different repo)

#### Files Modified

| File                                                         | Change                                                                            |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `projects/perses-shared/plugin-system/src/test/mock-data.ts` | Update `MOCK_ALERTS_DATA` and `MOCK_SILENCES_DATA` to use new generic type shapes |

#### Details

The model and runtime files in perses-shared (`alerts-queries.ts`, `silences-queries.ts`, `DataQueriesProvider.tsx`) work with
`AlertsData`/`SilencesData` opaquely — they don't access individual alert fields. Only the mock data constructs `Alert` and `Silence` objects
directly.

**`MOCK_ALERTS_DATA` (line 120-139):** Update from old format to new generic format:

```typescript
export const MOCK_ALERTS_DATA: AlertsData = {
  alerts: [
    {
      id: 'abc123',
      name: 'HighErrorRate',
      state: 'firing',
      labels: {
        alertname: 'HighErrorRate',
        severity: 'critical',
        service: 'backend',
      },
      annotations: {
        summary: 'High error rate detected',
      },
      severity: 'critical',
      startsAt: '2024-01-01T00:00:00Z',
      endsAt: '2024-01-02T00:00:00Z',
      updatedAt: '2024-01-01T12:00:00Z',
      receivers: ['cluster-01'],
    },
  ],
};
```

Changes: added `id`, `name`, `state`, `severity`; changed `receivers` from `[{ name }]` to `string[]`; removed `status` wrapper and `fingerprint`.

**`MOCK_SILENCES_DATA` (line 141-166):** Update from old format to new generic format:

```typescript
export const MOCK_SILENCES_DATA: SilencesData = {
  silences: [
    {
      id: 'silence-1',
      state: 'active',
      matchers: [
        {
          name: 'alertname',
          value: 'HighErrorRate',
          isRegex: false,
          isEqual: true,
        },
      ],
      startsAt: '2024-01-01T00:00:00Z',
      endsAt: '2024-01-02T00:00:00Z',
      createdBy: 'admin',
      comment: 'Maintenance window',
      updatedAt: '2024-01-01T00:00:00Z',
    },
  ],
};
```

Changes: `state` inlined from `status: { state }` wrapper; removed `annotations`.

#### Phase 1 Verification

- TypeScript compilation passes: `cd projects/perses-shared && npx turbo run build --filter=@perses-dev/plugin-system`
- Tests pass: `cd projects/perses-shared && npx turbo run test --filter=@perses-dev/plugin-system`

---

### Phase 2: perses-plugins — Update data transformation with mapping functions

**Dependency:** None **Parallel with:** Phase 1 (different repo)

#### Files Modified

| File                                                                                                | Change                                                                                        |
| --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `projects/perses-plugins/alertmanager/src/plugins/alertmanager-alerts-query/get-alerts-data.ts`     | Rewrite `transformAlert` to map AM API → generic Alert with state mapping                     |
| `projects/perses-plugins/alertmanager/src/plugins/alertmanager-silences-query/get-silences-data.ts` | Rewrite `transformSilence` to map AM API → generic Silence (inline state, remove annotations) |

#### Details

**`get-alerts-data.ts` — rewrite `transformAlert` (lines 22-39):**

Import `AlertState` and `SuppressionRule` from `@perses-dev/spec`. Add a `mapAlertState` helper. The mapping follows the table from the prior task's
plan.

```typescript
import { Alert, AlertState, AlertsData, SuppressionRule } from '@perses-dev/spec';

function mapAlertState(amState: 'active' | 'suppressed' | 'unprocessed'): AlertState {
  switch (amState) {
    case 'active':
      return 'firing';
    case 'suppressed':
      return 'firing';
    case 'unprocessed':
      return 'pending';
  }
}

function transformAlert(apiAlert: GettableAlert): Alert {
  const suppressedBy: SuppressionRule[] = [
    ...apiAlert.status.silencedBy.map((id) => ({ type: 'silence', id })),
    ...apiAlert.status.inhibitedBy.map((id) => ({ type: 'inhibition', id })),
    ...apiAlert.status.mutedBy.map((id) => ({ type: 'mute', id })),
  ];
  const isSuppressed = apiAlert.status.state === 'suppressed';

  return {
    id: apiAlert.fingerprint,
    name: apiAlert.labels['alertname'] ?? '',
    state: mapAlertState(apiAlert.status.state),
    labels: apiAlert.labels,
    annotations: apiAlert.annotations,
    severity: apiAlert.labels['severity'],
    startsAt: apiAlert.startsAt,
    endsAt: apiAlert.endsAt,
    updatedAt: apiAlert.updatedAt,
    sourceURL: apiAlert.generatorURL,
    suppressed: isSuppressed || undefined,
    suppressedBy: suppressedBy.length > 0 ? suppressedBy : undefined,
    receivers: apiAlert.receivers.map((r) => r.name),
  };
}
```

**AM → Generic field mapping:**

| AM Field                       | Generic Field                                    | Mapping             |
| ------------------------------ | ------------------------------------------------ | ------------------- |
| `fingerprint`                  | `id`                                             | Direct              |
| `labels.alertname`             | `name`                                           | Extract from labels |
| `status.state = 'active'`      | `state = 'firing'`                               | Map                 |
| `status.state = 'unprocessed'` | `state = 'pending'`                              | Map                 |
| `status.state = 'suppressed'`  | `state = 'firing'`, `suppressed = true`          | Split               |
| `labels.severity`              | `severity`                                       | Extract from labels |
| `status.silencedBy`            | `suppressedBy` entries with `type: 'silence'`    | Map each ID         |
| `status.inhibitedBy`           | `suppressedBy` entries with `type: 'inhibition'` | Map each ID         |
| `status.mutedBy`               | `suppressedBy` entries with `type: 'mute'`       | Map each ID         |
| `generatorURL`                 | `sourceURL`                                      | Rename              |
| `receivers[].name`             | `receivers`                                      | Extract names       |

**`get-silences-data.ts` — rewrite `transformSilence` (lines 21-38):**

```typescript
function transformSilence(apiSilence: GettableSilence): Silence {
  return {
    id: apiSilence.id,
    state: apiSilence.status.state,
    matchers: apiSilence.matchers.map((m) => ({
      name: m.name,
      value: m.value,
      isRegex: m.isRegex,
      isEqual: m.isEqual,
    })),
    startsAt: apiSilence.startsAt,
    endsAt: apiSilence.endsAt,
    createdBy: apiSilence.createdBy,
    comment: apiSilence.comment,
    updatedAt: apiSilence.updatedAt,
  };
}
```

Changes: `status: { state }` → `state` inlined; removed `annotations: {}`.

#### Phase 2 Verification

- TypeScript compilation passes: `cd projects/perses-plugins/alertmanager && npx tsc --noEmit`
- `get-alerts-data.ts` no longer references `apiAlert.receivers` as an array of objects — maps to `string[]`
- `get-silences-data.ts` no longer outputs `annotations` or `status` wrapper

---

### Phase 3: perses-plugins — Update UI components and model code

**Dependency:** Phase 2 **Parallel with:** None

#### Files Modified

| File                                                                                    | Change                                                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `projects/perses-plugins/alertmanager/src/components/StatusBadge.tsx`                   | Update `ALERT_STATUS_MAP` to use generic states (`firing`, `pending`, `suppressed`)                                                                                                                                             |
| `projects/perses-plugins/alertmanager/src/components/MatchersList.tsx`                  | Change import from `Matcher` to `SilenceMatcher`                                                                                                                                                                                |
| `projects/perses-plugins/alertmanager/src/plugins/alert-table/alert-table-model.ts`     | Update `deduplicateAlerts` to use `alert.id`; update `getGroupSummary` to use `alert.state` and `alert.suppressed`; rename `GroupSummary.silenced` → `suppressed`, `unprocessed` → `pending`                                    |
| `projects/perses-plugins/alertmanager/src/plugins/alert-table/AlertTablePanel.tsx`      | Update field accesses: `alert.status.state` → `alert.state`/`alert.suppressed`; `alert.fingerprint` → `alert.id`; `alert.labels['alertname']` → `alert.name` where appropriate; `alert.status?.silencedBy` → `alert.suppressed` |
| `projects/perses-plugins/alertmanager/src/plugins/silence-table/SilenceTablePanel.tsx`  | Update `silence.status?.state` → `silence.state`                                                                                                                                                                                |
| `projects/perses-plugins/alertmanager/src/plugins/silence-table/silence-table-model.ts` | Update `getSilenceFieldValue` to use `silence.state` instead of `silence.status?.state`                                                                                                                                         |

#### Details

##### StatusBadge.tsx

Update `ALERT_STATUS_MAP` (line 27-31):

```typescript
const ALERT_STATUS_MAP: Record<string, StatusConfig> = {
  firing: { label: 'Firing', color: 'error' },
  suppressed: { label: 'Silenced', color: 'warning' },
  pending: { label: 'Pending', color: 'default' },
  resolved: { label: 'Resolved', color: 'success' },
  inactive: { label: 'Inactive', color: 'default' },
};
```

The `SILENCE_STATUS_MAP` stays unchanged (silence states are the same: `active`/`expired`/`pending`).

##### MatchersList.tsx

Change import at line 15:

```typescript
import { SilenceMatcher } from '@perses-dev/spec';
```

Update `MatchersListProps` interface and `formatMatcher` parameter type to use `SilenceMatcher`. Since `SilenceMatcher.isRegex` and `isEqual` are now
optional, add defaults in `formatMatcher`:

```typescript
function formatMatcher(matcher: SilenceMatcher): string {
  let operator: string;
  if (matcher.isRegex) {
    operator = (matcher.isEqual ?? true) ? '=~' : '!~';
  } else {
    operator = (matcher.isEqual ?? true) ? '=' : '!=';
  }
  return `${matcher.name}${operator}"${matcher.value}"`;
}
```

##### alert-table-model.ts

**`deduplicateAlerts` (line 95):** Change `alert.fingerprint` → `alert.id`:

```typescript
} else if (alert.id) {
  key = alert.id;
}
```

**`GroupSummary` interface (line 71-77):** Rename fields to match generic model:

```typescript
export interface GroupSummary {
  total: number;
  firing: number;
  suppressed: number;
  pending: number;
  labelCounts?: Record<string, Record<string, number>>;
}
```

**`getGroupSummary` (lines 155-162):** Update state switch to use generic states and suppressed flag:

```typescript
for (const alert of alerts) {
  summary.total++;
  if (alert.suppressed) {
    summary.suppressed++;
  } else {
    switch (alert.state) {
      case 'firing':
        summary.firing++;
        break;
      case 'pending':
        summary.pending++;
        break;
    }
  }
  // labelCounts logic stays the same
}
```

##### AlertTablePanel.tsx

Key changes:

1. **Line 151:** `alert.status.state ?? 'unprocessed'` → `alert.suppressed ? 'suppressed' : alert.state`
2. **Line 153:** `alert.labels['alertname'] ?? ''` → `alert.name`
3. **Line 198:** `!alert.status?.silencedBy?.length` → `!alert.suppressed`
4. **Line 306:** `key={alert.fingerprint ?? idx}` → `key={alert.id ?? String(idx)}`
5. **Line 452-453:** Search filter `a.status?.state?.toLowerCase()` → `a.state.toLowerCase()` plus check `a.suppressed` for "silenced"/"suppressed"
   search terms
6. **GroupSummaryChips (lines 83-88):** Update chip labels:

```tsx
{summary.firing > 0 && <Chip label={`${summary.firing} firing`} color="error" size="small" />}
{summary.suppressed > 0 && <Chip label={`${summary.suppressed} silenced`} color="warning" size="small" />}
{summary.pending > 0 && <Chip label={`${summary.pending} pending`} color="default" size="small" />}
```

##### SilenceTablePanel.tsx

1. **Line 57 (renderSilenceCell):** `silence.status?.state ?? 'expired'` → `silence.state`
2. **Line 97 (SilenceRow):** `silence.status?.state === 'expired'` → `silence.state === 'expired'`
3. **Line 197 (filteredSilences):** `s.status?.state?.toLowerCase()` → `s.state.toLowerCase()`

##### silence-table-model.ts

**Line 74 (getSilenceFieldValue):** `silence.status?.state ?? ''` → `silence.state`

#### Phase 3 Verification

- TypeScript compilation passes: `cd projects/perses-plugins/alertmanager && npx tsc --noEmit`
- No remaining references to `alert.status.state`, `alert.fingerprint`, `alert.generatorURL` in source files
- No remaining references to `silence.status?.state`, `silence.annotations` in source files
- No imports of `Matcher` (bare) from `@perses-dev/spec` — only `SilenceMatcher`

---

### Phase 4: perses-plugins — Update all tests

**Dependency:** Phase 3 **Parallel with:** None

#### Files Modified

| File                                                                                                     | Change                                                                               |
| -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `projects/perses-plugins/alertmanager/src/plugins/alertmanager-alerts-query/get-alerts-data.test.ts`     | Update expected output to match new generic Alert shape                              |
| `projects/perses-plugins/alertmanager/src/plugins/alertmanager-silences-query/get-silences-data.test.ts` | Update expected output to match new generic Silence shape                            |
| `projects/perses-plugins/alertmanager/src/plugins/alert-table/alert-table-model.test.ts`                 | Update `makeAlert` helper and assertions to use generic Alert shape                  |
| `projects/perses-plugins/alertmanager/src/plugins/alert-table/alert-table-sorting.test.ts`               | Update `makeAlert` helper to use generic Alert shape                                 |
| `projects/perses-plugins/alertmanager/src/plugins/silence-table/silence-table-model.test.ts`             | Update `makeSilence` helper to use generic Silence shape                             |
| `projects/perses-plugins/alertmanager/src/components/StatusBadge.test.tsx`                               | Update test cases to use new generic state names                                     |
| `projects/perses-plugins/alertmanager/src/components/MatchersList.test.tsx`                              | No code changes needed — inline matcher objects are compatible with `SilenceMatcher` |

#### Details

##### get-alerts-data.test.ts

Update expected output in `transforms API alerts into AlertsData format` test (line 78-88):

```typescript
expect(result.alerts[0]).toEqual({
  id: 'abc123',
  name: 'HighMemory',
  state: 'firing',
  labels: { alertname: 'HighMemory', severity: 'critical', instance: 'server-1' },
  annotations: { summary: 'Memory usage is above 90%' },
  severity: 'critical',
  startsAt: '2024-01-01T00:00:00Z',
  endsAt: '2024-01-01T01:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
  sourceURL: 'http://prometheus.example/graph?...',
  receivers: ['default'],
});
```

Update `maps suppressed alerts with silencedBy info` test (lines 90-99):

```typescript
expect(result.alerts[1]?.suppressed).toBe(true);
expect(result.alerts[1]?.state).toBe('firing');
expect(result.alerts[1]?.suppressedBy).toEqual([
  { type: 'silence', id: 'silence-1' },
]);
```

##### get-silences-data.test.ts

Update expected output (line 80-89):

```typescript
expect(result.silences[0]).toEqual({
  id: 'silence-1',
  state: 'active',
  matchers: [{ name: 'alertname', value: 'HighMemory', isRegex: false, isEqual: true }],
  startsAt: '2024-01-01T00:00:00Z',
  endsAt: '2024-01-01T04:00:00Z',
  createdBy: 'admin',
  comment: 'Maintenance window',
  updatedAt: '2024-01-01T00:00:00Z',
});
```

Update status check (line 99):

```typescript
expect(result.silences[1]?.state).toBe('expired');
```

##### alert-table-model.test.ts

Update `makeAlert` helper (lines 17-27) to use generic Alert shape:

```typescript
const makeAlert = (overrides: Partial<Alert> = {}): Alert => ({
  id: 'abc123',
  name: 'TestAlert',
  state: 'firing',
  labels: { alertname: 'TestAlert', severity: 'critical' },
  annotations: {},
  severity: 'critical',
  startsAt: '2024-01-01T00:00:00Z',
  endsAt: '2024-01-01T01:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
  receivers: [],
  ...overrides,
});
```

Update `getGroupSummary` test (lines 143-158) — change AM states to generic states and suppressed flag:

```typescript
const alerts: Alert[] = [
  makeAlert({ state: 'firing' }),
  makeAlert({ state: 'firing' }),
  makeAlert({ state: 'firing', suppressed: true }),
  makeAlert({ state: 'pending' }),
];

const summary = getGroupSummary(alerts);
expect(summary).toEqual({
  total: 4,
  firing: 2,
  suppressed: 1,
  pending: 1,
});
```

Update deduplication tests to use `id` instead of `fingerprint`:

```typescript
makeAlert({ id: 'fp1', labels: { alertname: 'A', severity: 'critical' } }),
```

##### alert-table-sorting.test.ts

Update `makeAlert` helper (lines 17-26) — same generic Alert shape as above.

##### silence-table-model.test.ts

Update `makeSilence` helper (lines 17-28):

```typescript
const makeSilence = (overrides: Partial<Silence> = {}): Silence => ({
  id: 'silence-1',
  state: 'active',
  matchers: [{ name: 'alertname', value: 'Test', isRegex: false, isEqual: true }],
  startsAt: '2024-01-01T00:00:00Z',
  endsAt: '2024-01-01T02:00:00Z',
  createdBy: 'admin',
  comment: 'Test silence',
  updatedAt: '2024-01-01T00:00:00Z',
  ...overrides,
});
```

Update status field tests:

```typescript
// Line 71: getSilenceFieldValue status test
const silence = makeSilence({ state: 'active' });
expect(getSilenceFieldValue(silence, 'status')).toBe('active');
```

##### StatusBadge.test.tsx

Update alert variant tests to use new generic states:

```typescript
it('renders "Firing" for firing state', () => {
  render(<StatusBadge status="firing" variant="alert" />);
  expect(screen.getByText('Firing')).toBeInTheDocument();
});

it('renders "Silenced" for suppressed state', () => {
  render(<StatusBadge status="suppressed" variant="alert" />);
  expect(screen.getByText('Silenced')).toBeInTheDocument();
});

it('renders "Pending" for pending state', () => {
  render(<StatusBadge status="pending" variant="alert" />);
  expect(screen.getByText('Pending')).toBeInTheDocument();
});

it('defaults to alert variant when variant is omitted', () => {
  render(<StatusBadge status="firing" />);
  expect(screen.getByText('Firing')).toBeInTheDocument();
});
```

#### Phase 4 Verification

- All tests pass: `cd projects/perses-plugins/alertmanager && npm test`

---

### Phase 5: Local linking and end-to-end verification

**Dependency:** Phase 1, Phase 4 **Parallel with:** None

#### Details

Follow the linking process from the spec's hints section to verify everything works together:

```bash
# 1. Build spec, link with shared
cd projects/perses-spec/ts
npm install
npm run build

cd projects/perses-shared/plugin-system
npm install ../../perses-spec/ts

# 2. Build shared, link with perses
cd projects/perses-shared
npm install
npm run build
./scripts/link-with-perses/link-with-perses.sh --perses

# 3. Start perses backend
cd projects/perses
make build-cli
./scripts/api_backend_dev.sh --e2e

# 4. In a 2nd terminal, start the app in shared mode
cd projects/perses/ui/app
npm run start:shared

# 5. In a 3rd terminal, start the alertmanager plugin
cd projects/perses-plugins
projects/perses/bin/percli plugin start alertmanager

# 6. In a 4th terminal, start test alert manager and prometheus
cd projects/perses
podman compose --file dev/docker-compose.yaml --profile prometheus --profile avalanche --profile alertmanager up
```

#### Phase 5 Verification

- TypeScript compiles in all repos without errors
- Unit tests pass in perses-shared and perses-plugins
- The alertmanager plugin starts without errors
- Alert table displays alerts with correct states (Firing, Silenced, Pending)
- Silence table displays silences with correct states (Active, Expired, Pending)
- Silence creation form works
- Silence expiration works
- Search filtering works on both tables

## PR Strategy

No PRs will be created for this task. All changes are committed directly to the existing feature branches and linked locally for testing.

| Branch                           | Repository     | Description                                                           |
| -------------------------------- | -------------- | --------------------------------------------------------------------- |
| `feat/alertmanager-plugin-types` | perses-shared  | Updated mock data to use generic types                                |
| `feat/alert-manager-plugin`      | perses-plugins | Added AM → generic mapping functions, updated UI components and tests |
| `feat/alert-manager-plugin`      | perses         | No code changes — verified via linking                                |

## Verification

| Acceptance Criterion                                            | How to Verify                                                                                                                    |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| AlertManager datasource plugin refactored to use new alert type | `get-alerts-data.ts` uses `mapAlertState` and builds `SuppressionRule[]` from AM fields. Tests verify mapping.                   |
| Compatibility with Alert Manager API maintained                 | `api-types.ts` unchanged (AM API types stay as-is). `transformAlert`/`transformSilence` map every AM field to the generic model. |
| Alert related code in perses-shared refactored                  | `MOCK_ALERTS_DATA` and `MOCK_SILENCES_DATA` use new generic shapes. Tests pass.                                                  |
| Alert related code in perses repo refactored                    | Perses compiles with updated linked dependencies. No direct alert type usage exists in perses UI code.                           |

## Risks

| Risk                                                                     | Impact                                                                             | Mitigation                                                                                         |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Spec branch has additional changes not captured here                     | Mapping functions may be incomplete                                                | Verify spec types before implementing; re-read `alerts-data.ts` and `silences-data.ts`             |
| Search/filter behavior changes due to state rename                       | Users searching "active" won't find firing alerts                                  | Search filter in AlertTablePanel should map both old and new terms, or search on the display label |
| `SilenceMatcher.isEqual` becoming optional breaks downstream assumptions | Components assuming `isEqual` is always defined may behave differently             | Add `?? true` defaults in `formatMatcher` and wherever `isEqual` is accessed                       |
| Deduplication default mode change from `fingerprint` to `id`             | The field name changed but the data is the same (AM fingerprint is mapped to `id`) | No behavior change — `id` holds the same fingerprint value                                         |
| Test mocks may not cover edge cases for suppressed alerts                | Suppressed flag + state combination not tested                                     | Add test case for `state: 'firing', suppressed: true` in alert table model tests                   |

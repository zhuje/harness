# Plan: Refactor Alert TypeScript Interfaces to be Provider-Agnostic

## Problem

PR #21 in `perses-spec` introduced TypeScript types for alerts and silences (`AlertsQuery`, `SilencesQuery`) that directly mirror the Prometheus
Alertmanager API. This tight coupling makes it difficult to support other alerting providers (Grafana Alerting, PagerDuty, OpsGenie, Datadog,
VictoriaMetrics, Zabbix, etc.) in the future. The interfaces need to be refactored into a generic, provider-agnostic model while still fully
supporting the AlertManager data source through plugin-level mapping.

### Investigation: Alerting Framework Survey

A survey of 8 alerting frameworks was conducted to identify commonalities and inform the generic model:

| Provider            | State Lifecycle                              | Labels/Tags                     | Annotations                          | Severity Model                           | Silencing                                                | Unique Concepts                                                          |
| ------------------- | -------------------------------------------- | ------------------------------- | ------------------------------------ | ---------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Prometheus AM**   | active / suppressed / unprocessed            | `labels: Record<string,string>` | `annotations: Record<string,string>` | Convention via `labels.severity`         | Silences with matchers, inhibition rules, mute intervals | `fingerprint`, `receivers[]`, `inhibitedBy`, `mutedBy`                   |
| **Grafana**         | Normal / Pending / Alerting / NoData / Error | `labels`                        | `annotations`                        | Convention via labels                    | Delegates to embedded AM                                 | `folderUID`, `ruleGroup`, `for` duration, `isPaused`, `Recovering` state |
| **PagerDuty**       | triggered / acknowledged / resolved          | CEF fields                      | `custom_details`                     | `severity`: critical/error/warning/info  | Event orchestration, maintenance windows                 | Three-tier model (event/alert/incident), `urgency`, `escalation_policy`  |
| **OpsGenie**        | open / closed + acknowledged flag            | `tags: string[]`                | `details: Record<string,string>`     | `priority`: P1-P5                        | Snooze (per-alert, time-limited)                         | `alias` (dedup key), `entity`, `isSeen`, `snoozedUntil`, `count`         |
| **Datadog**         | OK / Warn / Alert / No Data                  | `tags: string[]`                | `message`                            | Thresholds (critical, warning, recovery) | `options.silenced`, downtimes                            | Monitor-centric model, `multi`, `query`                                  |
| **VictoriaMetrics** | inactive / pending / firing                  | `Labels`                        | `Annotations`                        | Convention via labels                    | Delegates to AM                                          | `Expr`, separate `ActiveAt`/`Start`/`ResolvedAt`, `value`                |
| **Zabbix**          | OK / Problem + acknowledged                  | `tags: [{tag,value}]`           | `opdata`                             | 6-level numeric (0-5)                    | Maintenance periods, manual close                        | Trigger/event/problem hierarchy, `cause_eventid`, nanosecond precision   |
| **Mimir AM**        | Same as Prometheus AM                        | Same as Prometheus AM           | Same as Prometheus AM                | Same as Prometheus AM                    | Same as Prometheus AM                                    | Multi-tenancy, sharding, per-tenant limits                               |

**Key findings:**

1. **Universal fields**: name/title, state, labels/tags, annotations/details, start time, source URL, unique ID
2. **Near-universal**: end/resolved time, updated time, severity/priority, suppression indicator
3. **Provider-specific**: receivers (AM), fingerprint (AM), acknowledged flag (PD/OpsGenie/Zabbix), incident hierarchy (PD), snooze (OpsGenie)
4. **State terminology varies widely** but maps to a common lifecycle: `inactive` -> `pending` -> `firing` -> `resolved`
5. **Suppression and acknowledgement are orthogonal to the main state** — they should be modeled as separate flags, not as state enum values

**Recommended generic state model:**

- Main states: `inactive`, `pending`, `firing`, `resolved`
- Orthogonal modifiers: `suppressed: boolean`, `acknowledged: boolean` (both optional)
- The AlertManager-specific `'active' | 'suppressed' | 'unprocessed'` maps as: `active` -> `firing`, `unprocessed` -> `pending`, `suppressed` ->
  `firing` + `suppressed: true`

## Current State

| Component          | File / Location                                         | Current Behavior                                                                                                                                                              |
| ------------------ | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Alert types        | `ts/src/dashboard/query-type/alerts-data.ts` (PR #21)   | `Alert` interface mirrors AM API: `AlertStatus` with `state: 'active' \| 'suppressed' \| 'unprocessed'`, `silencedBy`, `inhibitedBy`, `mutedBy`, `receivers[]`, `fingerprint` |
| Silence types      | `ts/src/dashboard/query-type/silences-data.ts` (PR #21) | `Silence` interface mirrors AM API: `Matcher` with `isEqual`/`isRegex`, `SilenceStatus` with `state: 'active' \| 'expired' \| 'pending'`                                      |
| Query type mapping | `ts/src/dashboard/query-type/query.ts` (PR #21)         | `QueryType` maps `AlertsQuery -> AlertsData`, `SilencesQuery -> SilencesData`                                                                                                 |
| Exports            | `ts/src/dashboard/query-type/index.ts` (PR #21)         | Re-exports `alerts-data` and `silences-data`                                                                                                                                  |
| Base metadata      | `ts/src/dashboard/query-type/base-metadata.ts`          | `BaseMetadata` with `notices` and `executedQueryString` — all data types extend this                                                                                          |
| Existing pattern   | `ts/src/dashboard/query-type/trace-data.ts`             | Example of a well-structured generic data type with domain-specific metadata extension                                                                                        |

## Changes

### Phase 1: Refactor `alerts-data.ts` to generic alert model

**Dependency:** None **Parallel with:** Phase 2 (different file)

#### Files Modified

| File                                         | Change                                                                                                             |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `ts/src/dashboard/query-type/alerts-data.ts` | Replace AM-coupled `Alert`, `AlertStatus`, `Receiver` with generic `Alert`, `AlertState`, and extensible structure |

#### Details

Replace the current AlertManager-specific interfaces with a generic model derived from the cross-provider analysis.

**Current `Alert` (AM-coupled):**

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
  generatorURL?: string;
  fingerprint: string;
}
```

**Proposed generic `Alert`:**

```typescript
export type AlertState = 'inactive' | 'pending' | 'firing' | 'resolved';

export interface Alert {
  /** Unique identifier for this alert instance */
  id: string;
  /** Alert name or title */
  name: string;
  /** Current alert state in the generic lifecycle */
  state: AlertState;
  /** Key-value labels identifying the alert */
  labels: Record<string, string>;
  /** Key-value annotations with additional context */
  annotations: Record<string, string>;
  /** Normalized severity level */
  severity?: string;
  /** ISO 8601 timestamp when the alert started firing */
  startsAt: string;
  /** ISO 8601 timestamp when the alert was resolved or is expected to expire */
  endsAt?: string;
  /** ISO 8601 timestamp of the last update to this alert */
  updatedAt?: string;
  /** URL linking back to the alert source */
  sourceURL?: string;
  /** Whether this alert is suppressed */
  suppressed?: boolean;
  /** Typed references to the suppression sources */
  suppressedBy?: SuppressionRule[];
  /** Whether a responder has acknowledged this alert */
  acknowledged?: boolean;
  /** Notification targets this alert is routed to */
  receivers?: string[];
}

export interface SuppressionRule {
  /** Suppression category — defined by each provider plugin */
  type: string;
  /** Identifier of the suppression source */
  id: string;
}

export interface AlertsData {
  alerts: Alert[];
  metadata?: AlertsMetadata;
}

export interface AlertsMetadata extends BaseMetadata {
  [key: string]: unknown;
}
```

**Design decisions:**

- `id` added as a universal identifier (was `fingerprint` in AM, `id` in PD/OpsGenie, `eventid` in Zabbix)
- `name` added as an explicit field (was embedded as `labels.alertname` in AM — the plugin is responsible for extracting it)
- `state` uses the generic lifecycle (`inactive`/`pending`/`firing`/`resolved`) instead of AM-specific states
- `suppressed` and `acknowledged` are orthogonal boolean flags, not part of the state enum — this matches PagerDuty, OpsGenie, and Zabbix models
- `suppressedBy` is a `SuppressionRule[]` instead of a flat `string[]` — each entry has a `type` (provider-defined category like `'silence'`, `'inhibition'`, `'mute'`) and an `id`, preserving the reason for suppression without coupling to AM-specific field names. AM maps `silencedBy` -> `{ type: 'silence', id }`, `inhibitedBy` -> `{ type: 'inhibition', id }`, `mutedBy` -> `{ type: 'mute', id }`
- `severity` is optional because providers vary widely (string label, P1-P5, 0-5 numeric) — the plugin normalizes its provider's model to a string
- `receivers` kept as an optional `string[]` — this is a cross-provider concept (AM receivers, Grafana contact points, PagerDuty services, OpsGenie responders). Simplified from `Receiver[]` to `string[]` since only the name is needed for filtering; the `Receiver` interface is removed
- `fingerprint` removed (replaced by generic `id`)
- `generatorURL` renamed to `sourceURL` (more generic term)
- `endsAt` and `updatedAt` made optional — not all providers supply both (e.g., OpsGenie has no `endsAt`)
- `AlertStatus` and `Receiver` interfaces removed entirely

**AlertManager plugin mapping guidance:**

The AlertManager plugin (in `perses-plugins`, out of scope for this task) would map its native API response to the generic model:

| AM Field                                        | Generic Field                               | Mapping             |
| ----------------------------------------------- | ------------------------------------------- | ------------------- |
| `fingerprint`                                   | `id`                                        | Direct              |
| `labels.alertname`                              | `name`                                      | Extract from labels |
| `status.state` = `'active'`                     | `state` = `'firing'`                        | Map                 |
| `status.state` = `'unprocessed'`                | `state` = `'pending'`                       | Map                 |
| `status.state` = `'suppressed'`                 | `state` = `'firing'`, `suppressed` = `true` | Split               |
| `labels.severity`                               | `severity`                                  | Extract from labels |
| `status.silencedBy`                             | `suppressedBy` entries with `type: 'silence'`    | Map each ID to `{ type: 'silence', id }` |
| `status.inhibitedBy`                            | `suppressedBy` entries with `type: 'inhibition'` | Map each ID to `{ type: 'inhibition', id }` |
| `status.mutedBy`                                | `suppressedBy` entries with `type: 'mute'`       | Map each ID to `{ type: 'mute', id }` |
| `generatorURL`                                  | `sourceURL`                                 | Rename              |
| `receivers[].name`                              | `receivers`                                 | Extract names       |

#### Phase 1 Verification

- TypeScript compilation passes: `cd ts && npx tsc --noEmit`
- No references to `AlertStatus`, `Receiver` interface types remain in `alerts-data.ts` (`receivers` field is now `string[]`)
- `AlertsData` interface is unchanged (still wraps `Alert[]` with optional metadata)
- `QueryType['AlertsQuery']` still resolves to `AlertsData`

### Phase 2: Refactor `silences-data.ts` to generic silence model

**Dependency:** None **Parallel with:** Phase 1 (different file)

#### Files Modified

| File                                           | Change                                                                                                            |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `ts/src/dashboard/query-type/silences-data.ts` | Replace AM-coupled `Silence`, `Matcher`, `SilenceStatus` with generic `Silence`, `SilenceMatcher`, `SilenceState` |

#### Details

**Current `Silence` (AM-coupled):**

```typescript
export interface Matcher {
  name: string;
  value: string;
  isEqual?: boolean;
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
  status: SilenceStatus;
  updatedAt: string;
  annotations: Record<string, string>;
}
```

**Proposed generic `Silence`:**

```typescript
export type SilenceState = 'active' | 'expired' | 'pending';

export interface SilenceMatcher {
  /** Label or field name to match against */
  name: string;
  /** Value to match */
  value: string;
  /** Whether this is an equality match (true) or negation (false). Defaults to true. */
  isEqual?: boolean;
  /** Whether the value is a regex pattern */
  isRegex?: boolean;
}

export interface Silence {
  /** Unique identifier */
  id: string;
  /** Current state of the silence */
  state: SilenceState;
  /** Matching criteria that determine which alerts this silence applies to */
  matchers: SilenceMatcher[];
  /** ISO 8601 timestamp when the silence becomes active */
  startsAt: string;
  /** ISO 8601 timestamp when the silence expires */
  endsAt: string;
  /** User or system that created the silence */
  createdBy: string;
  /** Human-readable reason for the silence */
  comment?: string;
  /** ISO 8601 timestamp of the last update */
  updatedAt?: string;
}

export interface SilencesData {
  silences: Silence[];
  metadata?: SilencesMetadata;
}

export interface SilencesMetadata extends BaseMetadata {
  [key: string]: unknown;
}
```

**Design decisions:**

- `Matcher` renamed to `SilenceMatcher` to avoid name collisions and improve clarity
- `isRegex` made optional (default `false`) — not all providers support regex matching
- `SilenceStatus` wrapper removed — `state` is inlined directly on `Silence` (simpler, and the wrapper added no value)
- `comment` made optional — not all providers require it
- `updatedAt` made optional
- `annotations` removed from `Silence` — this was AlertManager-specific and not a universal concept for silences. Annotations on alerts are universal;
  annotations on silences are not.
- The silence state lifecycle (`active`/`expired`/`pending`) is already fairly generic across providers that support silences (AM, Grafana, Mimir).
  Providers without native silences (PagerDuty, OpsGenie snooze, Datadog downtimes) have a more different model that would likely be a separate query
  type rather than mapped into this one.

**Cross-provider silence mapping:**

| Concept  | Prometheus AM          | Grafana            | Mimir              | OpsGenie (closest) | Datadog (closest)        |
| -------- | ---------------------- | ------------------ | ------------------ | ------------------ | ------------------------ |
| Silence  | `Silence`              | `Silence` (via AM) | `Silence` (via AM) | `Snooze` (partial) | `Downtime` (partial)     |
| State    | active/expired/pending | Same as AM         | Same as AM         | N/A (boolean flag) | active/disabled/canceled |
| Matchers | label matchers         | Same as AM         | Same as AM         | N/A                | scope/filter             |

#### Phase 2 Verification

- TypeScript compilation passes: `cd ts && npx tsc --noEmit`
- No references to `Matcher` (standalone), `SilenceStatus` types remain in `silences-data.ts`
- `SilencesData` interface is unchanged (still wraps `Silence[]` with optional metadata)
- `QueryType['SilencesQuery']` still resolves to `SilencesData`

### Phase 3: Verify query type mapping and exports

**Dependency:** Phase 1, Phase 2 **Parallel with:** None

#### Files Modified

| File                                   | Change                                                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `ts/src/dashboard/query-type/query.ts` | No changes expected — verify `AlertsQuery: AlertsData` and `SilencesQuery: SilencesData` mappings still work |
| `ts/src/dashboard/query-type/index.ts` | No changes expected — verify exports still work                                                              |

#### Details

This phase is verification-only. The `QueryType` mapping in `query.ts` references `AlertsData` and `SilencesData` by type name, which are unchanged.
The `index.ts` re-exports are file-level and also unchanged.

Confirm:

1. `query.ts` imports `AlertsData` and `SilencesData` — these type names are preserved, so no import changes needed
2. `index.ts` re-exports `'./alerts-data'` and `'./silences-data'` — file names are preserved
3. Full TypeScript compilation succeeds across the entire `ts/` package

#### Phase 3 Verification

- `cd ts && npx tsc --noEmit` passes with no errors
- `cd ts && npm test` passes (if tests exist)
- Spot-check: import `Alert` from the package and confirm it has the new generic shape (no `receivers`, no `fingerprint`, has `id`, `name`, `state`)

## PR Strategy

| PR | Repository  | Branch              | Description                                                              | Dependencies                           |
| -- | ----------- | ------------------- | ------------------------------------------------------------------------ | -------------------------------------- |
| 1  | perses-spec | Branch from `pr-21` | Refactor alert and silence TypeScript interfaces to be provider-agnostic | PR #21 must be the base (build on top) |

All changes fit in a single PR against the `pr-21` branch. The PR description should include:

- The investigation summary (alerting framework survey table)
- The mapping table showing how AlertManager fields map to the generic model
- A note that the AlertManager plugin mapping implementation is out of scope (separate task)

## Verification

| Acceptance Criterion                                            | How to Verify                                                                                                                                                                                                                              |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Investigation of other alerting frameworks is done              | The survey table in this plan documents 8 providers, their data models, commonalities, and differences. Include this analysis in the PR description.                                                                                       |
| TypeScript interface is generic and decoupled from AlertManager | `alerts-data.ts` no longer contains `AlertStatus`, `Receiver`, `fingerprint`, `inhibitedBy`, `mutedBy`, `silencedBy`, or AM-specific state values (`'active' \| 'suppressed' \| 'unprocessed'`). Uses generic states and universal fields. |
| AlertManager data source is still supportable via mapping       | The mapping table in Phase 1 demonstrates that every AM field can be mapped to the generic model. The generic model has `id`, `state`, `suppressed`, `suppressedBy` to capture all AM state information.                                   |
| No changes to other projects                                    | Only files in `perses-spec/ts/src/dashboard/query-type/` are modified. No changes to perses-plugins, perses-shared, perses, monitoring-plugin, or any other project.                                                                       |
| TypeScript compiles                                             | `cd ts && npx tsc --noEmit` passes                                                                                                                                                                                                         |

## Risks

| Risk                                                               | Impact                                                                                                        | Mitigation                                                                                                                                                                                                                     |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PR #21 changes before this lands                                   | Merge conflicts if PR #21 is rebased or amended                                                               | Coordinate with PR #21 author; rebase this work if needed                                                                                                                                                                      |
| Generic model misses a field needed by a future provider           | Provider plugin cannot fully map its data                                                                     | The `AlertsMetadata` allows `[key: string]: unknown` for extensibility; the generic interface can be extended later without breaking changes                                                                                   |
| Removing `annotations` from `Silence` breaks a downstream consumer | If any code in perses-plugins or monitoring-plugin reads `silence.annotations`, it would break when upgrading | Out of scope for this task, but the follow-up refactoring task for other projects should check for this. The `annotations` field on silences was only added in PR #21 which hasn't merged yet, so no existing consumers exist. |
| `Matcher` rename to `SilenceMatcher` breaks imports                | Code importing `Matcher` from perses-spec would fail                                                          | Same as above — PR #21 hasn't merged, so no existing consumers. The rename is safe.                                                                                                                                            |

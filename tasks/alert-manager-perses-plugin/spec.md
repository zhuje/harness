# Spec: Add an alert manager datasource plugin to Perses

## Related projects and branches

- perses: upstream branch `main`
- perses-shared: branch `main`
- perses-plugins: branch `main`
- perses-spec: branch `main`

## Description

To complete the troubleshooting experience that Perses provides, we need to add support for Alert Manager as a Perses plugin, the plugin module should
contain the following plugins:

- A datasource plugin to query Alert Manager for alerts and silences.
- An alert hierarchical table display plugin to visualize the alerts in a table format with default grouping and collapse expand the groups, including
  the alert name, severity, status, and other relevant information. As well as it silenced status and the silences that are currently active for the
  alert. The table should support grouping the alerts by its group or other fields like status or severity. Filtering should also be supported to
  easily find specific alerts.

for example:

```
Search: [ search bar ]
▼ Group by: [ alertname ✖ ] [ cluster ✖ ]                     [ Expand All ] [ Collapse All ]
─────────────────────────────────────────────────────────────────────────────────────────────
▶ 🚨 HighCPULoad (3 Firing)  |  clusters: prod-us, dev-eu  |  [ + Silence Group ]
─────────────────────────────────────────────────────────────────────────────────────────────
▶ 🚨 DatabaseLatency (15 Firing, 5 Silenced) | clusters: prod-us | [ + Silence Group ]
─────────────────────────────────────────────────────────────────────────────────────────────
▶ 🔕 KubePodCrashLooping (0 Firing, 12 Silenced) | clusters: dev-eu | [ + Silence Group ]
─────────────────────────────────────────────────────────────────────────────────────────────
```

and when expanding the group:

```
▼ 🚨 DatabaseLatency (15 Firing, 5 Silenced) | clusters: prod-us | [ + Silence Group ]
  ──────────────────────────────────────────────────────────────────────────────────
  ↳ 🔴 FIRING    | cluster: prod-us | db: users_db | node: db-01 | [ Silence ] [ Runbook ]
  ↳ 🔴 FIRING    | cluster: prod-us | db: users_db | node: db-02 | [ Silence ] [ Runbook ]
  ↳ ⚪ SILENCED  | cluster: prod-us | db: cache_db | node: db-05 | [ Edit Silence ]
      └─ Silenced by: jsmith@acme.com until 18:00 (Maintenance window)
  ↳ 🔴 FIRING    | cluster: prod-us | db: payments | node: db-01 | [ Silence ] [ Runbook ]
  ... (16 more rows)
```

- A silences hierarchical table display plugin to visualize the silences in a table format with default grouping and collapse expand the groups,
  including the silence name, status, and other relevant information. The table should support grouping the silences by their status (active, expired,
  pending) and other relevant fields. Filtering should also be supported to easily find specific silences. This should reuse the components and
  patterns used in the alert table.
- The alert and silences tables should support many "queries" so they are able to aggregate alerts and silences from different datasources, this will
  be useful in multi-cluster environments where each cluster has its own Alert Manager instance.
- An explore plugin to allow to manage silences, including creating, editing, and expiring silences.
- An explore plugin to query alerts.

The alert management should NOT be included in this plugin as this is managed via prometheus rules.

## Acceptance criteria

- A new plugin module, called `alert-manager`, is created in the `perses-plugins` repository adding support for Alert Manager datasource, panels and
  explore plugins for alerts and silences.
- The datasource plugin supports querying for alerts and silences.
- The alert and silences table plugins supports visualizing items in a hierarchical table format with grouping and filtering capabilities.
- The explore plugins support managing silences and querying alerts.

## Hints

- A new query type might be needed as Alerts and Silences have a different data structure not currently supported.

## Out of scope

- Alert management via prometheus rules.

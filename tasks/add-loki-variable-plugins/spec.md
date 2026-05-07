# Spec: Add Variable plugins to the Loki Perses plugin

## Related projects and branches

- perses-plugins: branch `main`

## Description

Simlar to the prometheus plugin, we want to add support for variables in the Loki plugin. This will allow users to create dashboards that can use loki
queries as variable values. We need to add suppport for the labels, label names and a LogQL query variable type. Same as prometheus.

## Acceptance criteria

- The loki plugin module supports a LokiLabelValuesVariableplugin
- The loki plugin module supports a LokiLabelNamesVariableplugin
- The loki plugin module supports a LokiLogQLVariableplugin

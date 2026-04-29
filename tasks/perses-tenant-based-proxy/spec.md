# Spec: Support tenant-based proxy in Perses datasource proxy

## Related projects and branches

- perses: upstream branch `main`
- monitoring-plugins: branch `main`

## Description

Currently perses datasource proxy url is static, meaning variables cannot be used to interpolate the URL. In some cases a tenant header or custom
query parameter is required. The monitoring plugin, uses Perses plugin and compoents in embeeded mode to allow visualization of dashboards from the
OpenShift console, when the changes in perses are complete, I need to include them downtream in the monitoring plugin.

## Acceptance criteria

- The datsource proxy used in the Prometheus datasource in Perses supports to interpolate headers and custom query parameters using the current
  variable values in the dashboard.
- A PR or set of PRs are created upstream in Perses including the change to interpolate headers and custom query parameters in the datasource proxy.
- The monitoring plugin used in the OpenShift console is updated with the latest plugin versions and can send request to a datasource proxy with
  interpolated values.

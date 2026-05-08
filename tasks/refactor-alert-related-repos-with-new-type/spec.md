# Spec: Support tenant-based proxy in Perses datasource proxy

## Related projects and branches

- perses-spec: branch `feat/alertmanager-plugin-types`
- perses: upstream branch `feat/alert-manager-plugin`
- perses-shared: branch `feat/alertmanager-plugin-types`
- perses-plugins: branch `feat/alert-manager-plugin`

## Description

After the plan `plan/refactor-alert-manager-data-type` was implemented, The plugin, shared and perses repos were not updated with the new type. This
task is to refactor the alert related code in these repos to use the new type, while maintaning compatibility with the Alert Manager API by mapping
the alert manager specific fields to the ones defined in the spec.

## Acceptance criteria

- The alert manager datasource plugin should be refactored to use the new alert type defined in the spec, while maintaining compatibility with the
  Alert Manager API.
- The alert related code in the perses shared repo should be refactored to use the new alert type defined in the spec, while maintaining compatibility
  with the Alert Manager API.
- The alert related code in the perses repo should be refactored to use the new alert type defined in the spec, while maintaining compatibility with
  the Alert Manager API.

## Hints

Use the following process to link the packages together:

```bash
# link spec with shared plugin-system
cd <path to perses spec>/ts
npm install
npm run build
ccd <path to perses shared>/plugin-system
npm install <relative path to perses spec e.g. "../../spec/ts">
# link shared with perses
cd <path to perses shared>
npm install
npm run build
./scripts/link-with-perses/link-with-perses.sh --perses

# start perses backend
cd <path to perses>
make build-cli
./scripts/api_backend_dev.sh --e2e

# in a 2nd terminal, start the app in shared mode
cd <path to perses>/ui/app
npm run start:shared

# in a 3rd terminal, start the plugin
cd <path to perses plugins>
<path to perses/bin/percli plugin start alertmanager

# in a 4th terminal, start the test alert manager and prometheus
cd <path to perses>
podman compose --file dev/docker-compose.yaml --profile prometheus --profile avalanche --profile alertmanager up
```

# Plan: Upgrade Perses and Perses-Operator Forks for COO 1.5.0

## Problem

The COO 1.5.0 release requires upgrading the Perses and Perses-operator forks in `github.com/rhobs` to the latest upstream versions. The current fork
branches (`v0.53-golang_1_25` and `v0.3-golang_1_25`) need to be replaced with new `release-coo-1.5` branches aligned with the operator version naming
convention. Four repositories are affected in dependency order: rhobs/perses, rhobs/perses-operator, observability-operator, and konflux-coo.

## Current State

| Repository             | Current Branch      | Commit                       | Version           |
| ---------------------- | ------------------- | ---------------------------- | ----------------- |
| rhobs/perses           | `v0.53-golang_1_25` | `06294bc78873`               | v0.53.0           |
| rhobs/perses-operator  | `v0.3-golang_1_25`  | `755ff584dc8b`               | v0.3.0            |
| observability-operator | `main`              | go.mod refs above commits    | v0.53.1 / v0.1.10 |
| konflux-coo            | `release-1.5`       | submodules ref above commits | --                |

## Changes

### Phase 1: Determine Latest Upstream Versions

- Check latest release tags on `perses/perses` and `perses/perses-operator`
- Review changelogs for breaking changes since current fork versions
- Known breaking changes in perses-operator: optional API fields refactored to pointer types, secret label filtering for optimized watching

### Phase 2: Create rhobs/perses `release-coo-1.5` Branch

- Sync `rhobs/perses` fork with upstream `perses/perses`
- Create branch `release-coo-1.5` from latest main
- Create a script to adjust the fork:
  - Change the go module so it contains the rhobs repo instead of the upstream perses paths, do the same with imports.
  - Remove CI jobs.
  - include the `plugins-archive` directory in the branch, as it is needed for including the perses plugins in COO.
- Remove old plugins versions from `plugins-archive`, the `build-api` command below should fetch the latest versions.
- Verify perses build: `make build-api && make build-cli`

### Phase 3: Create rhobs/perses-operator `release-coo-1.5` Branch

- Sync `rhobs/perses-operator` fork with upstream `perses/perses-operator`
- Create branch `release-coo-1.5` from latest upstream release tag
- Create a script to adjust the fork:
  - Change the go module so it contains the rhobs repo instead of the upstream perses paths, do the same with imports.
  - Remove CI jobs.
- Ensure `go.mod` references `rhobs/perses` fork's `release-coo-1.5` branch
- Verify build: `make bin`

### Phase 4: Update observability-operator

#### Files Modified

| File                                            | Change                                                                         |
| ----------------------------------------------- | ------------------------------------------------------------------------------ |
| `go.mod`                                        | Update `rhobs/perses` and `rhobs/perses-operator` to `release-coo-1.5` commits |
| `pkg/controllers/uiplugin/monitoring.go`        | Fix API type changes: wrap optional fields with `ptr.To()`                     |
| `pkg/controllers/uiplugin/accelerators.go`      | Fix `Client.TLS.Enable` to use `ptr.To(true)`                                  |
| `deploy/perses/crds/*.yaml`                     | Replace with CRDs from new perses-operator version                             |
| `deploy/perses/perses-operator-deployment.yaml` | Update operator image reference, enable TLS from k8s API server flags          |

#### Go Dependencies Update

```sh
go get github.com/rhobs/perses@release-coo-1.5
go get github.com/rhobs/perses-operator@release-coo-1.5
go mod tidy
```

#### API Type Changes (monitoring.go `newPerses()`, line 287)

Fields requiring `ptr.To()` wrapping if upstream moved to pointer types:

- `Image: persesImage` -> `Image: ptr.To(persesImage)`
- `ContainerPort: 8080` -> `ContainerPort: ptr.To(int32(8080))`
- `TLS.Enable: true` -> `Enable: ptr.To(true)` (3 occurrences)
- `SecretSource.Name` and `SecretSource.Namespace` -> `ptr.To(...)` (4 occurrences)
- `PrivateKeyPath: "tls.key"` -> `ptr.To("tls.key")`
- `KubernetesAuth.Enable: true` -> `ptr.To(true)`
- `ServiceAccountName` -> `ptr.To(...)`

Note: `ptr` package (`k8s.io/utils/ptr`) is already imported in monitoring.go for PodSecurityContext.

#### Secret Label for Optimized Watching

The perses-operator runs as a separate controller manager (see `deploy/perses/perses-operator-deployment.yaml`). If the new version filters secrets by
`perses.dev/watch=true`, the OpenShift service-ca TLS cert secret may need this label. Investigate whether:

- The TLS cert is consumed as a volume mount only (label unnecessary)
- The Perses CR spec supports propagating labels to managed secrets
- A new label watch can be added to the perses operator configuration in addition to the `perses.dev/watch=true` to watch for secrets in COO
  namespace, in particular secrets containing the CA so the perses operator can contact perses instances

#### Perses-Operator TLS from K8s API Server

The new perses-operator supports fetching TLS profile configuration from the OpenShift `APIServer` resource and propagating it to managed Perses pods.
Update `deploy/perses/perses-operator-deployment.yaml` to add the following flags to the container args:

- `--tls-cluster-profile` — fetches TLS min version and cipher suites from the OpenShift `config.openshift.io/v1 APIServer` resource, watches for
  changes and triggers graceful operator restart
- `--tls-configure-operands` — propagates the TLS settings (min version, cipher suites) to managed Perses pods via `--web.tls-min-version` and
  `--web.tls-cipher-suites` arguments
- Verify the operator's RBAC (`deploy/perses/perses-operator-cluster-role.yaml`) includes permissions to `get`, `list`, `watch` the
  `config.openshift.io/v1 APIServer` resource

#### CRD Updates

Copy from perses-operator fork's `config/crd/bases/` into `deploy/perses/crds/`:

- `perses.dev_perses.yaml`
- `perses.dev_persesdashboards.yaml`
- `perses.dev_persesdatasources.yaml`
- `perses.dev_persesglobaldatasources.yaml`

Use the `generate-perses-op-crds` to update the Perses CRs. Review `deploy/perses/crds/patches/` and `kustomization.yaml` for compatibility. Check if
any manual copy is needed.

### Phase 5: Update konflux-coo

#### Files Modified

| File                         | Change                                                                                 |
| ---------------------------- | -------------------------------------------------------------------------------------- |
| `.gitmodules`                | Update perses branch to `release-coo-1.5`, perses-operator branch to `release-coo-1.5` |
| `Dockerfile.perses`          | Update `VERSION` arg to new version, update `cpe` label from `1.4` to `1.5`            |
| `Dockerfile.perses-operator` | Update `VERSION` arg to new version, update `cpe` label from `1.4` to `1.5`            |

#### Submodule Updates

```sh
# After updating .gitmodules branches
git submodule update --remote perses perses-operator
```

#### Dockerfile Version Labels

- `Dockerfile.perses`: `ARG VERSION=v0.53.0` -> new version, `ARG VERSION=v0.54.0` as upstream versions need to be kept even if the branch name is
  different
- `Dockerfile.perses-operator`: `ARG VERSION=v0.3.0` -> new version, `ARG VERSION=v0.4.0` as upstream versions need to be kept even if the branch name
  is different

#### Tekton Pipelines

The existing pipelines (`.tekton/perses-1-5-*.yaml`, `.tekton/perses-operator-1-5-*.yaml`) trigger on `release-1.5` and reference `./perses` and
`./perses-operator` paths. No changes expected unless upstream build structure changed.

#### Image SHA References

`bundle-patches/render_templates` SHA-pinned images update automatically via Konflux build nudge.

## Verification

- `go build ./...` in observability-operator with updated dependencies
- `go test ./pkg/controllers/uiplugin/...` -- unit tests pass
- CRDs validate with `kubectl apply --dry-run=server`
- Perses CR from `newPerses()` validates against new CRDs
- Docker builds succeed for both Dockerfiles in konflux-coo
- Functional: deploy COO on test cluster, verify Perses instance with TLS is created and operational

## Risks

- Type conflicts between upstream `perses/perses` and fork `rhobs/perses` imports (existing workaround in accelerators.go:136)

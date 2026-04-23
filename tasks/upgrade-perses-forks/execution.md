# Execution: Upgrade Perses and Perses-Operator Forks for COO 1.5.0

## Phase 1: Determine Latest Upstream Versions (prerequisite for all other phases)

- [x] Check latest release tag on `github.com/perses/perses` — **v0.53.1** (main also at v0.53.1)
- [x] Check latest release tag on `github.com/perses/perses-operator` — **v0.3.2** (main also at v0.3.2)
- [x] Review perses changelog for breaking changes since v0.53.0 — **none**
- [x] Review perses-operator changelog for breaking changes since v0.3.0:
  - `[BREAKINGCHANGE]` enforce label `perses.dev/watch=true` to watch user-provided secrets
  - `[FEATURE]` watch TLS profiles and apply to operands (`--tls-cluster-profile`, `--tls-configure-operands`)
  - `[ENHANCEMENT]` improve manager caching when watching secrets
  - API types: rhobs fork uses direct values (`bool`, `string`, `int32`), upstream uses pointers (`*bool`, `*string`, `*int32`)
- [x] Confirm upstream Go toolchain version compatibility with Go 1.25 — **compatible**

## Phase 2: Create rhobs/perses `release-coo-1.5` Branch

Depends on: Phase 1

- [x] Sync `rhobs/perses` fork with upstream `perses/perses`
- [x] Create branch `release-coo-1.5` from latest upstream main (commit `6bc07370`, v0.53.1)
- [x] Create a script to adjust the fork (`adjust-perses-fork.sh`):
  - [x] Replace go module path from `github.com/perses/perses` to `github.com/rhobs/perses`
  - [x] Update all import paths to match the new module path (Go, CUE, Makefile, templates)
  - [x] Remove CI jobs (GitHub Actions workflows)
  - [x] Include the `plugins-archive` directory in the branch (un-ignore in .gitignore)
- [x] Remove old plugin versions from `plugins-archive` — empty on new branch, no cleanup needed
- [x] Verify build: `make build-api` succeeds on unmodified branch
- [x] Run `adjust-perses-fork.sh` and commit
- [x] Cherry-pick non-automated patches: Dockerfile.dev changes, K8s authorization fallback patch
- [x] Push branch to `rhobs/perses`

## Phase 3: Create rhobs/perses-operator `release-coo-1.5` Branch

Depends on: Phase 2 (needs rhobs/perses fork commit for go.mod reference)

- [x] Sync `rhobs/perses-operator` fork with upstream `perses/perses-operator`
- [x] Create branch `release-coo-1.5` from latest upstream main (commit `5701f3e`, v0.3.2)
- [x] Create a script to adjust the fork (`adjust-perses-operator-fork.sh`):
  - [x] Replace go module path from `github.com/perses/perses-operator` to `github.com/rhobs/perses-operator`
  - [x] Update all import paths to match the new module path
  - [x] Remove CI jobs (GitHub Actions workflows)
- [x] Fix `github.com/perses/spec` type incompatibility: embed canonical spec types in v1alpha2/v1alpha1 CRD wrapper types instead of deprecated types
      from renamed module (to be upstreamed)
- [x] Script includes `replace` directive for `github.com/rhobs/perses@release-coo-1.5`
- [x] Verify build: `make bin` succeeds on unmodified branch
- [x] Run `adjust-perses-operator-fork.sh` and commit (after Phase 2 push)
- [x] Push branch to `rhobs/perses-operator`

## Phase 3.5: Build and Push Upstream Images

Depends on: Phases 2 and 3 (needs fork branches pushed with working builds)

Both the observability-operator and konflux-coo reference container images for perses and perses-operator. New images must be built from the
`release-coo-1.5` branches and pushed before updating the references.

### Perses image

- [x] Build perses image from `rhobs/perses@release-coo-1.5` (using `Dockerfile.dev`)
- [x] Push to `quay.io/openshift-observability-ui/perses:v0.54.0`
- [x] Record the new image tag — **`v0.54.0`**

### Perses-operator image

- [x] Build perses-operator image from `rhobs/perses-operator@release-coo-1.5`
- [x] Push to `quay.io/openshift-observability-ui/perses-operator:v0.4.0`
- [x] Record the new image tag — **`v0.4.0`**

### Update image references in observability-operator

- [x] `cmd/operator/main.go` — `perses:v0.53.0-go-1.25` → `perses:v0.54.0`
- [x] `deploy/operator/kustomization.yaml` — `perses:v0.53.0-go-1.25` → `perses:v0.54.0`
- [x] `deploy/perses/perses-operator-deployment.yaml` — `perses-operator:v0.3.0-go-1.25` → `perses-operator:v0.4.0`
- [x] `bundle/manifests/observability-operator.clusterserviceversion.yaml` — both perses and perses-operator image tags updated
- [x] Verify no old `go-1.25` image tags remain — **none found**
- [x] Verify `go build ./...` still passes — **passes**

---

## Phase 4 and 5 can run in parallel after Phases 2, 3, and 3.5 are complete

---

## Phase 4: Update observability-operator (Agent A)

Depends on: Phases 2 and 3 (needs final commit SHAs from both fork branches)

### 4a. Go dependency update

- [x] Run `go get github.com/rhobs/perses@release-coo-1.5` — resolved to `v0.0.0-20260422074433-2c06d5cd1312`
- [x] Run `go get github.com/rhobs/perses-operator@release-coo-1.5` — resolved to `v0.1.10-0.20260422102948-9bec730aa616`
- [x] Add `replace` directives for `controller-runtime-common` and `controller-runtime` to maintain compatibility with pinned `openshift/api`
- [x] Fix API type changes: `Datasource.DatasourceSpec` → `Datasource.Spec` (now `github.com/perses/spec/go/datasource.Spec`),
      `Dashboard.DashboardSpec` → `Dashboard.Spec`
- [x] Update imports: add `specCommon`, `dsSpec` from `github.com/perses/spec/go/*`; remove unused `persescommon`
- [x] Run `go mod tidy`
- [x] Verify `go build ./...` compiles — **passes**

### 4b. Fix API type changes

- [x] Update `pkg/controllers/uiplugin/monitoring.go` — `newPerses()` function:
  - [x] `Image: persesImage` -> `Image: ptr.To(persesImage)`
  - [x] `ContainerPort: 8080` -> `ContainerPort: ptr.To(int32(8080))`
  - [x] `TLS.Enable: true` -> `Enable: ptr.To(true)` (3 occurrences: TLS, Client.TLS, KubernetesAuth)
  - [x] `SecretSource.Name` and `Namespace` fields -> `ptr.To(...)` (4 SecretSource structs)
  - [x] `PrivateKeyPath: "tls.key"` -> `ptr.To("tls.key")`
  - [x] `KubernetesAuth.Enable: true` -> `ptr.To(true)`
  - [x] `ServiceAccountName` -> `ptr.To(...)`
- [x] Update `pkg/controllers/uiplugin/accelerators.go` — `newAcceleratorsDatasource()`:
  - [x] `Client.TLS.Enable: true` -> `Enable: ptr.To(true)`
- [x] Verify compilation: `go build ./...` — **passes**

### 4c. Secret label for optimized watching

- [x] Investigate if perses-operator filters secrets by `perses.dev/watch=true` label — **yes, cache-level filter in `internal/cache/options.go`**
- [x] Determine if the OpenShift service-ca TLS cert secret needs this label — **NO, not needed**
  - The operator only watches secrets for `Spec.Provisioning.SecretRefs`, not TLS secrets
  - TLS secrets are mounted as volumes by Kubernetes, not read via operator cache
  - `findPersesForSecret` handler only checks provisioning secret refs
- [x] No implementation needed — label filtering does not affect TLS cert operation

### 4d. Perses-operator TLS flags

- [x] Update `deploy/perses/perses-operator-deployment.yaml`:
  - [x] Add `--tls-cluster-profile` flag to container args
  - [x] Add `--tls-configure-operands` flag to container args
- [x] Update `deploy/perses/perses-operator-cluster-role.yaml`:
  - [x] Add RBAC permissions to `get`, `list`, `watch` `config.openshift.io/v1 APIServer` resources

### 4e. CRD updates

- [x] Run `generate-perses-op-crds` make target to update CRDs (added `ignoreUnexportedFields=true` flag to Makefile)
- [x] Verify updated CRDs in `deploy/perses/crds/` — all 4 CRDs regenerated
- [x] Review `deploy/perses/crds/patches/` and `kustomization.yaml` — webhook patches and annotations intact
- [x] No manual copy needed — make target handled everything

### 4f. Verification

- [x] `go build ./...` — **passes**
- [x] `go test ./pkg/controllers/uiplugin/...` — **passes** (0.908s)
- [ ] CRDs validate with `kubectl apply --dry-run=server`

## Phase 5: Update konflux-coo (Agent B)

Depends on: Phases 2 and 3 (needs fork branches to exist for submodule update)

### 5a. Update submodule references

- [x] Update `.gitmodules` perses branch from `v0.53-golang_1_25` to `release-coo-1.5`
- [x] Update `.gitmodules` perses-operator branch from `v0.3-golang_1_25` to `release-coo-1.5`
- [x] Run `git submodule update --init --remote perses perses-operator`
- [x] Verify submodule pointers resolve to correct commits:
  - perses: `2c06d5cd1312` (release-coo-1.5)
  - perses-operator: `9bec730aa616` (release-coo-1.5)

### 5b. Update Dockerfiles

- [x] `Dockerfile.perses`:
  - [x] Update `ARG VERSION=v0.53.0` to `ARG VERSION=v0.54.0`
  - [x] Update `cpe` label from `1.4` to `1.5`
  - [x] Verify `make build-api` and `make build-cli` targets still exist in upstream Makefile
  - [x] Verify `plugins-archive/` is produced by `build-api` → `generate` → `install-default-plugins`
- [x] `Dockerfile.perses-operator`:
  - [x] Update `ARG VERSION=v0.3.0` to `ARG VERSION=v0.4.0`
  - [x] Update `cpe` label from `1.4` to `1.5`
  - [x] Verify `make bin` target still exists in upstream Makefile

### 5c. Review Tekton pipelines

- [x] Verify `.tekton/perses-1-5-push.yaml` and `.tekton/perses-1-5-pull-request.yaml` — **OK**
- [x] Verify `.tekton/perses-operator-1-5-push.yaml` and `.tekton/perses-operator-1-5-pull-request.yaml` — **OK**
- [x] Confirm prefetch-input gomod paths (`./perses`, `./perses-operator`) — **valid**
- [x] No old branch name references found in pipeline files

### 5d. Verification

- [x] Submodules resolve to correct commits on `release-coo-1.5` branches
- [x] Docker build dry-run for `Dockerfile.perses`
- [x] Docker build dry-run for `Dockerfile.perses-operator`

---

## Phase 6: End-to-End Verification (after Phases 4 and 5)

- [x] Deploy COO on test cluster with updated dependencies
- [x] Verify Perses instance is created with TLS enabled
- [x] Verify perses-operator reconciles the Perses CR successfully
- [x] Verify TLS cluster profile flags are active in operator logs
- [x] Verify dashboards and datasources are created and synced
- [ ] Verify Konflux pipelines trigger and produce valid images

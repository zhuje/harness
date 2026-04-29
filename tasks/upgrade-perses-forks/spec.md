# Spec: Upgrade perses and perses operator forks for COO release 1.5.0

## Related projects and branches

- perses: branch in the fork `rhobs/release-coo-1.5`
- perses-operator: branch in the fork `rhobs/release-coo-1.5`
- observability-operator: branch `main`
- konflux-coo: branch `release-1.5`

## Description

In preparation of the COO release 1.5.0, we need to upgrade perses and perses operator forks present in the github.com/rhobs org to the latest
version. This will help to update them to include them in the productization pipeline: konflux-coo. A new branch naming convention should be used to
align with the operator version, in this case rhobs/perses/release-coo-1.5 and rhobs/perses-operator/release-coo-1.5 should be created with the latest
versions.

## Acceptance criteria

- New branches github.com/rhobs/perses/release-coo-1.5 and github.com/rhobs/perses-operator/release-coo-1.5 are created with the latest versions of
  the upstream corresponding repositories.
- The observability operator dependencies are updated to use the new branches of perses and perses-operator forks as go dependencies. Since it embeeds
  the perses operator component:
  - Based on the last changes related to TLS and secret labels for optimized watching in the perses operator, the observability operator is updated to
    create the Perses instance correctly.
  - The perses CRDs present in the observability operator are updated to match the latest versions of the perses operator, including any changes
    related to TLS and secret labels for optimized watching.
- konflux-coo is updated to use the new branches of perses and perses-operator, including changes to the Dockerfiles and the git submodules
  references.

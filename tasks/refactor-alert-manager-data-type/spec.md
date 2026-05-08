# Spec: Support tenant-based proxy in Perses datasource proxy

## Related projects and branches

- perses-spec: pr #21

## Description

After the plan `plan/alert-manager-perses-plugin` was implemented, I realized that the spec typescript interface related to alerts is too coupled with
the AlertManager data model, which is not ideal since it makes it harder to support other data sources related to alerting in the future. I need to
refactor the typescript interface to be more generic and decoupled from the AlertManager data model while still supporing the AlertManager data
source.

## Acceptance criteria

- An investigation is done as part of the plan to dientify other alerting framkeworsks and providers, their data models are analyzed and the
  commonalities and differences with the AlertManager data model are identified.
- The typescript interface related to alerts is refactored to be more generic and decoupled from the AlertManager data model, while still supporting
  the alert manager fields even if this requires mapping in the AlertManager plugin.

## Out of scope

- Refactor the alert manager plugin perses plugin, perses shared and perses repos. This will be part of a different task. Do NOT refactor other
  projects in this task, only the typescript interface related to alerts in the spec.

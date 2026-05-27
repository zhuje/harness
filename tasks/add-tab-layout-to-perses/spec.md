# Spec: Add Tab layout to Perses

## Related projects and branches

- perses: branch `main`
- perses-shared: branch `main`
- perses-spec: branch `main`

## Description

The current layour for Perses uses a collection of Grids that are stacked vertically and can be collapsed, inside each grid a set of panels can be
placed. A new proposal based on this Github issue: https://github.com/perses/perses/issues/4067 was posted. The goal is to add a new Layout that
allows to display the panel groups in horizontal tabs, this will allow to have quick access to related panel groups without having to scroll all the
way down. This change should be additive and keep the backwards compatibility with the current grid.

## Acceptance criteria

- There is a new "Tabs" layout that can group panels, the panels inside each tab can be arranged and resized inside a grid.
- The whole tabs group can be collapsed or expanded
- A dashboard can support both Grid and Tabs layouts simultaneously
- While editing each tab layout all the tab display names can be changed and tabs can be re ordered, also it can be defined which one is the default
  tab
- New e2e tests exist in perses ui to validate the new layout with testing dashboards

## Hints

- The current grid layout is located in: `projects/perses-shared/dashboards/src/components/GridLayout/index.ts`
- The dashboard rendering the grid is located in: `projects/perses-shared/dashboards/src/components/Dashboard/Dashboard.tsx`

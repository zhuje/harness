# Spec: Add an alert manager datasource plugin to Perses

## Related projects and branches

- perses-plugins: branch `main`

## Description

The current logs table does not parse ansi symbols for logs descriptions that include coloring. This task is to add support for parsing ansi symbols
in the logs table plugin in a safe way.

## Acceptance criteria

- The logs table plugin can parse ansi symbols in log descriptions and render them as colored text in the UI.
- The implementation should be secure and not allow for any potential XSS vulnerabilities.
- The feature should be tested with various log entries that include different types of ansi color codes to ensure proper rendering.

## Hints

- The logs table is located in projects/perses-plugins/logstable

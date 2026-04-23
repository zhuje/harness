# Observability UI AI SDLC Harness

AI-driven software development lifecycle harness for the Observability UI team. This repo provides structured context, task tracking, and automation
for using AI coding agents across the team's project portfolio.

## How it works

Each task follows a three-document workflow:

1. **`description.md`** - Problem statement, related projects/branches, and acceptance criteria.
2. **`work-plan.md`** - Step-by-step breakdown an AI agent can execute against.
3. **`execution.md`** - Progress tracking with checkboxes and notes captured during execution.

Tasks live in `tasks/` while active and move to `completed/` when done. The `projects/` directory contains git submodules for every repo in scope,
giving agents direct access to source code.

## Projects

See [projects/README.md](projects/README.md) for the full list of repositories in scope.

## Repository layout

```
tasks/                  # Active tasks (description + work-plan + execution)
completed/              # Archived completed tasks
projects/               # Git submodules for all in-scope repos
bin/                    # Local tooling (dprint)
.claude/                # Claude Code agent configuration
```

## Setup

```sh
git clone --recurse-submodules https://github.com/observability-ui/harness/
make tools    # install dprint for markdown formatting
```

## Markdown formatting

All markdown is formatted with [dprint](https://dprint.dev/) (150 char line width). Run `make lint` to format and `make check` to validate.

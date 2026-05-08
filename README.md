# Observability UI AI SDLC Harness

AI-driven software development lifecycle harness for the Observability UI team. This repo provides structured context, task tracking, and automation
for using AI coding agents across the team's project portfolio.

## How it works

Each task follows a three-document workflow:

1. **`spec.md`** - Problem statement, related projects/branches, and acceptance criteria.
2. **`plan.md`** - Step-by-step breakdown an AI agent can execute against.
3. **`execution.md`** - Progress tracking with checkboxes and notes captured during execution.

Tasks live in `tasks/`. The `projects/` directory contains git submodules for every repo in scope, giving agents direct access to source code.

## Projects

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full project catalog and system architecture.

## Repository layout

```
tasks/                  # Active tasks (description + work-plan + execution)
completed/              # Archived completed tasks
projects/               # Git submodules for all in-scope repos
bin/                    # Local tooling (dprint)
claude/plugins/obsui/   # Claude Code plugin for assisted development and code reviews
```

## Setup

```sh
git clone --recurse-submodules https://github.com/observability-ui/harness/
make setup    # install tools and reset submodules to their configured branches
```

## Resetting projects

After working on tasks, submodules may have checked-out branches or uncommitted changes. Run `make reset-projects` to reset all submodules back to the branches defined in `.gitmodules` at the latest remote HEAD. This prevents intermediate states from being committed to this meta-repo.

## Markdown formatting

All markdown is formatted with [dprint](https://dprint.dev/) (150 char line width). Run `make lint` to format and `make check` to validate.

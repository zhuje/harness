# obsui — Claude Code Plugin

Development assistant for the observability UI team.

## Skills

| Skill           | Invoke                      | Description                                                                              |
| --------------- | --------------------------- | ---------------------------------------------------------------------------------------- |
| `planner`       | `/obsui:planner <task>`     | Create an implementation plan from a spec, with phases, dependencies, and risk analysis  |
| `executor`      | `/obsui:executor <task>`    | Parse a plan into an execution checklist and execute phases with parallel agents and TDD |
| `code-reviewer` | `/obsui:code-reviewer <PR>` | Multi-phase PR review using Opus lead + Sonnet specialists                               |

### Workflow

The skills form a pipeline: **spec → plan → execution → review**.

```
tasks/<task>/spec.md
        │
        ▼
  /obsui:planner <task>
        │
        ▼
tasks/<task>/plan.md
        │
        ▼
  /obsui:executor <task>
        │
        ▼
tasks/<task>/execution.md
        │
        ▼
  /obsui:code-reviewer <PR>
```

1. Write a `spec.md` in `tasks/<task>/` describing the problem and requirements
2. Run `/obsui:planner <task>` — asks clarifying questions, explores the codebase, produces `plan.md`
3. Run `/obsui:executor <task>` — generates `execution.md`, then executes each phase (using TDD for implementation phases, parallel agents for
   independent phases)
4. Run `/obsui:code-reviewer <PR>` — reviews the resulting pull request

### Planner

```
/obsui:planner alert-manager-perses-plugin
```

**Input:** A task folder under `tasks/` containing `spec.md`.

**What it does:**

- Reads the spec, `ARCHITECTURE.md`, and per-project `CLAUDE.md`/`AGENTS.md`
- Asks 5–10 clarifying questions before exploring
- Explores the codebase (launches parallel agents for multi-repo tasks)
- Produces `plan.md` with phases, file modification tables, code details, verification commands, PR strategy, and risk analysis

### Executor

```
/obsui:executor alert-manager-perses-plugin
```

**Input:** A task folder under `tasks/` containing `plan.md` (produced by the planner).

**What it does:**

- Parses the plan and generates `execution.md` — a rich checklist with phase dependencies, parallel group separators, and verification steps
- Classifies each phase as `implementation` (TDD required), `configuration`, or `investigation`
- Presents an execution summary and waits for confirmation before starting
- Executes phases in dependency order, dispatching parallel agents when phases touch different repos
- Enforces TDD (Red-Green-Refactor) for implementation phases, matching each project's test conventions
- Tracks progress with inline result annotations and handles failures with a structured decision tree

**Prerequisites:** Submodule directories must be configured in `.claude/settings.json` under `additionalDirectories` (or use `--add-dir` flags) to
avoid permission prompts when agents access project files. See the skill file for details.

### Code Reviewer

```
/obsui:code-reviewer 123
/obsui:code-reviewer https://github.com/org/repo/pull/123
```

**Input:** A PR number or GitHub PR URL.

**What it does:**

- Gathers PR metadata, diff, and file contents
- Phase 1: Opus lead reviewer identifies bugs, security issues, and scopes specialist reviews
- Phase 2: Sonnet agents review in parallel based on tech stack (Go, TypeScript, config, etc.)
- Synthesizes findings with Critical/Important/Nit severity levels

## Installation

### From a local path (session only)

Load the entire plugin for a single session:

```bash
claude --plugin-dir /path/to/ai-sdlc/claude/plugins/obsui
```

This loads all three skills for the session. Changes to skill files take effect on the next invocation — no restart needed.

### From the marketplace (permanent)

Add the repo as a marketplace, then install the plugin:

```bash
/plugin marketplace add observability-ui/harness
/plugin install obsui@harness
```

After installation, the plugin loads automatically on every session start. Use `/reload-plugins` to pick up changes without restarting.

### Install LSP plugins (optional)

Install the official LSP plugins for TypeScript and Go from the Claude Code marketplace:

```bash
/plugin install typescript-lsp@claude-plugins-official
/plugin install gopls-lsp@claude-plugins-official
```

These plugins require the language server binaries on your system:

```bash
# TypeScript
npm install -g typescript-language-server typescript

# Go
go install golang.org/x/tools/gopls@latest
```

LSP is optional — reviews work without it, but type info and reference counts improve accuracy.

### Verify installation

Start a Claude Code session and check the plugin is loaded:

```
/plugins
```

The `obsui` plugin and its three skills should appear in the list.

## Development

Edit skill files directly under `skills/<skill-name>/SKILL.md`. Changes take effect on the next skill invocation — no restart needed. Run
`/reload-plugins` to pick up structural changes (new skills, renamed directories).

### Plugin structure

```
obsui/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── skills/
│   ├── planner/
│   │   └── SKILL.md         # Spec → plan skill
│   ├── executor/
│   │   └── SKILL.md         # Plan → execution skill
│   └── code-reviewer/
│       └── SKILL.md         # PR review skill
└── README.md
```

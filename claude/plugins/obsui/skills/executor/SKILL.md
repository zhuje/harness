---
name: executor
description: Parse a plan.md into a rich execution.md, then execute each phase using parallel agents where possible, tracking progress and handling failures.
allowed-tools: Read, Write, Edit, Bash, Agent, LSP
---

## Input

$ARGUMENTS is a task folder name. The folder must exist under `tasks/` and contain a `plan.md` file.

## Prerequisites

The projects referenced in the plan live as git submodules under `projects/`. Ensure each submodule is listed in `.claude/.settings.json` under
`permissions.additionalDirectories` (or start the session with `--add-dir` flags).

**Path rules — ALWAYS use relative paths from the repo root:**

- File reads: `projects/<project>/path/to/file` (no leading `./`)
- Bash find/grep/ls: `./projects/<project>/...`
- Git in submodules: `git -C ./projects/<project> <command>` or `cd ./projects/<project> && git ...`
- NEVER use absolute paths — they trigger permission prompts for untrusted hooks
- Agent prompts MUST use these relative forms in Setup sections

## Steps

### 1. Validate and load context

Read these files in order:

```
tasks/$ARGUMENTS/plan.md        (required — stop if missing)
tasks/$ARGUMENTS/spec.md        (optional — for acceptance criteria cross-reference)
ARCHITECTURE.md                 (required — for project catalog and dependency chains)
```

For each project, check the current branch and switch to the correct one as specified in the spec "Related projects and branches" section (if it
exists) or the plan's "PR Strategy" section:

```bash
git -C ./projects/<project> branch --show-current
git -C ./projects/<project> checkout <target-branch>
```

Then for each project referenced in the plan's "Files Modified" tables, read if they exist:

```
projects/<project>/CLAUDE.md
projects/<project>/AGENTS.md
```

After reading, extract and hold:

- The list of phases with their dependencies and parallel annotations
- The list of projects/repos touched by each phase (derived from file paths like `project-name/path/to/file.ext`)
- Per-project build and test commands from CLAUDE.md/AGENTS.md
- The spec's acceptance criteria (if spec.md exists)

**Discover build and test commands per project:**

For each project touched by `implementation` phases, discover the project's own build/test/lint commands and testing conventions:

```bash
# Check Makefile targets (Go and mixed projects)
grep -E '^[a-zA-Z_-]+:' ./projects/<project>/Makefile 2>/dev/null | head -20

# Check package.json scripts (JS/TS projects)
grep -A 30 '"scripts"' ./projects/<project>/package.json 2>/dev/null

# Find test files to detect naming convention
find ./projects/<project> -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "*_test.go" \) | head -10
```

**Command rules:** NEVER run `npx` commands directly — they trigger permission prompts. Always use Makefile targets or npm scripts like
`npm run build`, `npm run test`, `npm run lint` or `npm run type-check`. Go commands (`go test`, `go build`) are fine.

Record per project:

- **Build command**: Makefile target or npm script (e.g., `make build`, `npm run build`)
- **Test runner**: Makefile target or npm script (e.g., `make test`, `npm test`, `go test ./...`)
- **Lint command**: Makefile target or npm script (e.g., `make lint`, `npm run lint`)
- **Test file naming**: `*.test.ts`, `*.spec.ts`, `*_test.go`, etc.
- **Test file location**: colocated with source, or `__tests__`/`test`/`tests` directory
- **Test framework**: Jest, Vitest, Go testing, etc.

This information is pasted into agent prompts so agents use the correct project commands.

Verify that each project directory referenced in the plan exists under `projects/`. If any are missing, warn the user — they may need to initialize
submodules or configure `additionalDirectories`.

### 2. Generate execution.md

Parse each phase from the plan and generate `tasks/$ARGUMENTS/execution.md`.

**Extraction rules:**

For each phase in the plan's Changes section:

1. Extract the phase name, dependency, and parallel annotations verbatim
2. From the **Files Modified** table, create one checkbox item per row: `- [ ] [Change description] - \`file/path\``
3. From the **Details** section, extract any investigation or decision items as separate checkboxes (e.g., "Investigate whether...")
4. From the **Phase N Verification** section, create verification checkboxes under a sub-heading
5. Derive the list of projects touched from file paths in the Files Modified table

**Phase classification:**

Each phase gets a `Type:` annotation that determines how it is executed:

- `implementation` — creates or modifies behavior (new functions, API changes, refactoring, new components). **Agents must follow TDD**
  (Red-Green-Refactor).
- `configuration` — mechanical changes with no behavioral logic (version bumps, import updates, go.mod, config files, Dockerfiles). No TDD required.
- `investigation` — research or decision tasks (check upstream versions, determine compatibility, investigate behavior). No TDD required. After
  completing an investigation phase, one of three outcomes applies:
  1. **Value discovered** — annotate the result inline (`-- **v0.53.1**`). Later phases consume it. No new tasks.
  2. **Decision: not needed** — annotate and proceed (`-- **NO, not needed**`). No new tasks.
  3. **New work discovered** — add an emergent phase to execution.md (see Step 6) and update dependency annotations for affected phases.

Classification rules:

- If the phase's Files Modified table includes source files (`.go`, `.ts`, `.tsx`) with changes described as "add", "create", "implement", "refactor",
  or "update logic" → `implementation`
- If the changes are "bump version", "update import", "update reference", "change config value" → `configuration`
- If the changes are "check", "verify", "investigate", "determine" → `investigation`
- When in doubt, classify as `implementation` — TDD overhead is low, skipping it risks quality

**Sub-phase decomposition rules:**

- Phase touches 2+ repos → one sub-phase per repo (e.g., 4a for repo A, 4b for repo B)
- Phase Details has `#####` sub-sections → one sub-phase per sub-section
- Phase mixes implementation and investigation → separate sub-phases
- Simple single-repo phases → stay flat (no sub-phases)

**Parallel group separators:**

When consecutive phases can run in parallel, insert a separator:

```
---
## Phases 4 and 5 can run in parallel after Phases 2 and 3
---
```

Save the file using this format:

```
# Execution: [Task Name from plan title]

> Results are annotated inline: `-- **value**` for discovered values, `-- **passes/FAILED**` for verification.

## Phase 1: [Phase Name]
Depends on: nothing | Parallel with: none | Type: investigation | Projects: project-a

- [ ] [Description from Files Modified table] - `project-a/path/to/file.ext`

### Phase 1 Verification
- [ ] [Command from plan] - expected: [outcome]

## Phase 2: [Phase Name]
Depends on: Phase 1 | Parallel with: Phase 3 (different repos) | Type: implementation | Projects: project-a

### 2a. [Sub-phase for distinct concern]
- [ ] Write failing tests for [behavior] - `project-a/path/to/file.test.ext`
- [ ] Implement [change] to pass tests - `project-a/path/to/file.ext`

### 2b. [Sub-phase for another concern]
- [ ] Write failing tests for [behavior] - `project-a/path/to/file.test.ext`
- [ ] Implement [change] to pass tests - `project-a/path/to/file.ext`

### Phase 2 Verification
- [ ] All new tests pass
- [ ] All existing tests pass
- [ ] [Command] - expected: [outcome]

--- Phases 3 and 4 can run in parallel after Phase 2 ---

## Phase 3: [Phase Name]
Depends on: Phase 2 | Parallel with: Phase 4 (different repo) | Type: configuration | Projects: project-b

- [ ] [Description] - `project-b/path/to/file.ext`

### Phase 3 Verification
- [ ] [Command] - expected: [outcome]
```

### 3. Present execution strategy to user

Before executing, present a summary and wait for confirmation:

```
## Execution Summary

**Total phases:** N
**Parallel groups:** [which phases can run in parallel, e.g., "Phases 3+4 after Phase 2"]
**Projects touched:** [list of project directories]

### Git strategy
[For each project, state the branch from the plan's PR Strategy section]
- projects/<project>: branch `<branch>` from `<base>`

### Phases requiring human action
[List any phases involving actions Claude cannot perform: pushing to remotes, deploying, running CI]
- Phase N: [what the user needs to do]

Proceed with execution?
```

Use `AskUserQuestion` for confirmation. If the user wants changes, update execution.md and re-present.

### 4. Execute phases

Process phases in dependency order. For each phase:

**a. Check dependencies**

Verify all prerequisite phases are marked complete in execution.md. If not, skip and return later.

**b. Determine execution mode**

- **Direct execution**: Phase touches 1-2 files in one repo, changes are mechanical (config values, version bumps, import updates). Execute the
  changes yourself without dispatching an agent. Always `cd` into `./projects/<project>/` (with `./` prefix) and create/checkout the feature branch
  (`feat/<feature-name>`) there before making changes. Never create feature branches from the repository root. Never use absolute paths.
- **Single agent**: Phase is complex but self-contained to one repo (API type changes, refactoring, new implementation). Dispatch one agent.
- **Parallel agents**: Two or more phases are annotated as parallelizable and touch different repos or non-overlapping files. Dispatch agents in a
  single message with multiple Agent tool calls so they run concurrently.

For parallel agents touching different submodules: since submodules are separate git repos, agents naturally avoid file conflicts. For parallel agents
modifying different files within the same repo, use `isolation: "worktree"` on the Agent tool call to create isolated checkouts.

**c. Compose agent prompts**

Each agent gets a self-contained prompt — do not make agents read plan.md. Paste everything they need.

Use this template for all phase types. Include the TDD section only for `implementation` phases.

````
## Task: Phase N - [Phase Name]

## What to do

[FULL TEXT of the phase's Details section from plan.md]

## Files to modify

| File | Change |
| ---- | ------ |
| `project/path/to/file.ext` | [Change description from plan] |

## Context

Working directory: projects/<project>/
Branch: <branch name>

[Paste relevant CLAUDE.md/AGENTS.md content for this project]
[Paste ARCHITECTURE.md excerpts if cross-repo awareness is needed]

## Setup (run first)

```bash
cd ./projects/<project> && git checkout -b feat/<feature-name>
```

Branch: `feat/<feature-name>` in lowercase kebab-case, derived from the plan title or phase description.
All subsequent commands must run from inside `./projects/<project>/`. Use `./` prefix on all paths — never absolute paths.

## [FOR implementation PHASES ONLY — include this section]

### Development method: TDD (mandatory)

#### Test conventions for this project

- **Test file naming:** [e.g., `*.spec.ts` | `*.test.ts` | `*_test.go`]
- **Test location:** [e.g., colocated with source | `__tests__/` directory | same package]
- **Build command:** [e.g., `npm run build` | `make build` | `go build ./...`]
- **Test runner:** [e.g., `npm test` | `make test` | `go test ./...`]
- **Lint command:** [e.g., `npm run lint` | `make lint`]
- **Test framework:** [e.g., Jest | Vitest | Go testing]

NEVER run `npx` commands directly (e.g., `npx jest`, `npx tsc`, `npx vitest`, `npx eslint`). Always use the Makefile target or npm script listed
above. Go commands (`go test`, `go build`) are fine to use directly.

Follow these conventions exactly. Before writing any test, find an existing test in this project and match its style.

#### Red-Green-Refactor cycle

For every behavioral change:

1. **RED** — Write a failing test. Run it. Confirm it fails for the right reason.
2. **GREEN** — Write minimal code to pass. Run it. Confirm all tests pass.
3. **REFACTOR** — Clean up. Keep tests green.

Rules:
- No production code without a failing test first
- One behavior per test, clear test name
- Use real code, not mocks (unless dependency is unavoidable)
- If a test passes immediately, fix the test — it tests existing behavior
- If you wrote code before the test, delete it and start over

## [END implementation-only section]

## Constraints

- Only modify listed files unless the change requires additional files (report which and why)
- Follow existing code and test patterns in this project
- Run verification commands after making changes
- Commit with a descriptive message when verification passes

## Verification

[Paste the Phase N Verification items from the plan]

## Report format

When done, report:

- **Status:** DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
- **Files changed:** list each file with a brief description
- [FOR implementation PHASES] **Tests written:** each new test with name and behavior it verifies
- [FOR implementation PHASES] **TDD evidence:** for each test, confirm RED before GREEN
- **Verification results:** exact command output for each verification item
- **Issues:** unexpected issues, decisions made, or deviations from the plan
````

**d. Handle agent status**

- `DONE` → run verification (Step 5), mark checkboxes in execution.md, annotate results, proceed
- `DONE_WITH_CONCERNS` → read concerns. If about correctness or scope, address before proceeding. If observational (e.g., "file is getting large"),
  note in execution.md and proceed.
- `NEEDS_CONTEXT` → provide the missing context and re-dispatch the agent
- `BLOCKED` → go to Step 6 (failure handling)

**e. Annotate results inline**

After each checkbox item completes, annotate the result in execution.md:

```
- [x] Check latest release tag on perses/perses -- **v0.53.1**
- [x] Run go build ./... -- **passes**
- [x] Investigate whether label filtering affects TLS -- **NO, not needed**
- [ ] Deploy on test cluster -- [HUMAN]
```

**f. Handle human-action phases**

For phases that require actions Claude cannot perform (pushing to remotes, deploying to clusters, running CI pipelines), present what needs to happen
and wait for the user to confirm completion before proceeding.

### 5. Phase verification

After each phase completes (whether executed directly or by an agent):

1. Run each verification command from the plan's "Phase N Verification" section (follow command rules from Step 1).
2. Annotate the result in execution.md:
   - Pass: `- [x] make build -- **passes**`
   - Fail: `- [ ] npm test -- **FAILED: TestFoo expected X got Y**`
3. **For `implementation` phases**, additionally verify TDD compliance:
   - Confirm the agent report includes "TDD evidence" showing RED before GREEN for each test
   - Confirm new tests exist for every behavioral change
   - Run the full test suite for the affected project using the project's test command (e.g., `make test`, `npm test`, `go test ./...`)
   - If the agent skipped TDD or wrote code before tests, reject the work and re-dispatch with explicit TDD instructions
4. If all verification passes, proceed to the next phase
5. If any verification fails, go to Step 6

### 6. Handle failures

| Failure type                                                 | Action                                              | Limit                              |
| ------------------------------------------------------------ | --------------------------------------------------- | ---------------------------------- |
| Build/compilation error                                      | Read error, attempt fix, re-verify                  | 2 attempts → stop, present to user |
| Test failure                                                 | Diagnose real bug vs. test issue, attempt fix       | 2 attempts → stop, present to user |
| Dependency/environment (missing tools, network, permissions) | Stop, present to user                               | —                                  |
| Plan is wrong (invalid assumption, approach fails)           | Mark **BLOCKED** in execution.md, suggest amendment | —                                  |

**Emergent phases:**

When execution reveals work not anticipated in the original plan (e.g., needing to build container images before updating references):

1. Add a new phase to execution.md with an incremental number (e.g., "Phase 3.5: [Description]")
2. Add a note explaining why it was added: `> Added during execution: [reason]`
3. Update dependency annotations for subsequent phases
4. Execute the new phase before continuing with dependent phases

### 7. Final verification and summary

After all phases complete:

1. Run the end-to-end verification items from the plan's "Verification" section
2. Cross-reference against the spec's acceptance criteria (if spec.md was loaded in Step 1)
3. Append a summary section to execution.md:

```
---

## Summary

**Status:** Complete | Partial (N of M phases done)

### Outstanding items

- [ ] [Items requiring human action]
- [ ] [Items blocked on external dependencies]

### Notes

- [Decisions made during execution that deviated from the plan]
- [Issues discovered that may affect future work]
- [Emergent phases added and why]
```

4. If the plan includes a PR Strategy section, present the current git state for each project and suggest next steps (create branches, push, create
   PRs)

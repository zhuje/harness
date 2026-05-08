---
name: planner
description: Create an implementation plan for a given spec, breaking it down into phases with file tables, code details, parallel execution annotations, verification, and risk analysis.
allowed-tools: Read, Bash(find:*), Bash(grep:*), Bash(rg:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git branch:*), Bash(git -C:*), Bash(wc:*), Bash(ls:*), LSP, Agent
---

## Input

$ARGUMENTS is a task folder name. The folder must exist under `tasks/` and contain a `spec.md` file.

## Prerequisites

The projects referenced in the spec live as git submodules under `projects/`. The repository's `.claude/settings.json` already includes
`additionalDirectories` for the project submodules, so file reads and bash commands against those paths will not trigger permission prompts.

**Path rules — ALWAYS use relative paths from the repo root:**

- File reads: `projects/<project>/path/to/file` (relative, no leading `./`)
- Bash find/grep/ls: `./projects/<project>/...`
- Git commands in submodules: `git -C ./projects/<project> <command>` (e.g., `git -C ./projects/perses log --oneline -5`)
- NEVER use absolute paths or `cd /absolute/path && git ...` — these trigger permission prompts for untrusted hooks
- The permission allowlist matches `cd ./projects/* && git *`, so if you must use `cd`, always use the relative form: `cd ./projects/<project> && git ...`

## Steps

### 1. Read the spec and system context

Read these files in order:

```
tasks/$ARGUMENTS/spec.md
ARCHITECTURE.md
```

For each project listed in the spec's "Related projects and branches" section:

1. Check the current branch and recent commits:

```bash
git -C ./projects/<project> branch --show-current && echo "---" && git -C ./projects/<project> log --oneline -5
```

2. Use the Read tool with relative paths to read these files if they exist:

- `projects/<project>/CLAUDE.md`
- `projects/<project>/AGENTS.md`
- `projects/<project>/README.md`

Run all project checks and reads in parallel across projects to minimize round-trips.

After reading, identify:

- Which repositories are in scope (from the spec's "Related projects and branches")
- The dependency order between them (from ARCHITECTURE.md)
- What the spec is asking for (the change) vs. why (the motivation)
- Which acceptance criteria are concrete and verifiable vs. ambiguous

### 2. Clarify requirements

Ask the user 5-10 questions before exploring the codebase. The goal is to eliminate ambiguity and reduce risk before investing time in exploration.
Present all questions in a single message.

**Prioritize questions that would change the plan structure.** Do not ask questions you can answer by reading the codebase. Skip questions whose
answers are obvious from the spec.

Good questions target:

- **Ambiguous acceptance criteria** (e.g., "latest versions" — release tag or tip of main?)
- **Scope boundaries** (e.g., CI pipelines in scope or only source code?)
- **Ordering constraints** (e.g., PRs merge in order or reviewed in parallel?)
- **Risk areas the spec doesn't mention** (e.g., Go module type incompatibilities?)
- **Target branches and release alignment**
- **Testing expectations** (e.g., test cluster available or stop at unit tests?)

Use AskUserQuestion for questions with clear options (scope, ordering, yes/no decisions). Use a numbered list for open-ended questions (risk areas,
testing expectations, design trade-offs).

Wait for the user's answers before proceeding to Step 3.

### 3. Explore the codebase

Explore with focused intent based on the spec and the user's answers.

**Multi-repo tasks:** When multiple repos are in scope, launch parallel Explore agents (one per repo) to investigate simultaneously. Each agent should
report: project structure, files that will be modified, current behavior of affected code, and relevant patterns. Synthesize their findings before
writing the plan.

**Single-repo tasks:** Explore directly without sub-agents.

For each repository in scope, investigate:

**Project structure:**

```bash
find projects/<project> -maxdepth 3 -type f \( -name "*.go" -o -name "*.ts" -o -name "*.tsx" \) | head -40
ls projects/<project>/
```

**Files that will change:**

```bash
grep -rn "functionName\|TypeName\|pattern" projects/<project>/src/ --include="*.ts"
find projects/<project> -path "*/path/to/area/*" -type f
```

**Current behavior** (for the plan's "Current State" table):

Read the files that will be modified. Use LSP when available to get precise type signatures, reference counts, and call hierarchies for the symbols
being modified.

**Dependencies and blast radius:**

```bash
grep -rn "import.*module" projects/<project>/
git -C ./projects/<project> log --oneline -10 -- path/to/file
```

**Similar implementations** (patterns to follow):

```bash
grep -rn "similar_pattern" projects/<project>/
```

**Cross-repo contracts** (multi-repo tasks only):

- Check API contracts between repos (types, interfaces, Go module references)
- Identify the dependency chain (which repo changes must land first)
- Note deployment ordering constraints (backend before frontend, operator before operand)

### 4. Write the plan

Use the template below. Every section is required. Adjust depth to match complexity: a fork upgrade may be 150 lines; a multi-repo feature with new
APIs may be 500+.

**Detail calibration:**

- **Code snippets:** Include for type signature changes, API contract changes, non-obvious logic, tricky merge patterns
- **Line references:** Include when the exact insertion/modification point matters (e.g., "line 287 in monitoring.go where the struct literal must
  change")
- **Prose:** Use for straightforward file copies, config value updates, dependency bumps
- **Files Modified table:** Required for every phase that modifies files — this is the most actionable part of the plan for the executing agent

**Parallel execution annotations:**

Each phase must declare its dependency and whether it can run in parallel with other phases. The constraint: only one agent should modify a given file
at a time. Phases touching different repos or non-overlapping files can run in parallel via separate agents.

### 5. Self-review

Before saving, verify the plan against the spec:

1. **Acceptance criteria coverage** — every spec criterion is addressed by a phase/task; Verification section covers all criteria, not just easy ones
2. **Dependency ordering and parallelism** — phases reference correct dependencies, no phase uses output from a later phase, parallel phases don't modify overlapping files
3. **File path accuracy** — every path exists in the codebase or is marked as a new file
4. **Component reuse** — new components/functions placed in the right directory given their consumers across all phases

### 6. Save

Save the plan as `tasks/$ARGUMENTS/plan.md`.

## Plan template

```
# Plan: [Task Name]

## Problem

[Why this change is needed. Link upstream issues if relevant. Explain the business or technical motivation, not just what will change.]

## Current State

| Component | File / Location | Current Behavior |
| --------- | --------------- | ---------------- |
| [name]    | `project/path/to/file.ext:line` | [What it does now] |
| ...       | ...             | ...              |

## Changes

### Phase 1: [Name]

**Dependency:** None
**Parallel with:** None | Phase N (when touching different repos/files)

#### Files Modified

| File | Change |
| ---- | ------ |
| `project/path/to/file.ext` | [Brief description of what changes] |
| ...  | ...    |

#### Details

[Detailed description of the changes. Include code snippets for type changes and non-obvious logic. Include line references when the exact point matters.]

##### [Sub-section for complex changes within this phase]

[For phases with multiple independent changes, use sub-sections.]

#### Phase 1 Verification

- [Specific command and expected output]
- [Manual check if automated verification is not possible]

### Phase 2: [Name]

**Dependency:** Phase 1
**Parallel with:** Phase 3 (different repo)

[Same structure as Phase 1]

...

## PR Strategy

| PR | Repository | Branch | Description | Dependencies |
| -- | ---------- | ------ | ----------- | ------------ |
| 1  | [repo]     | [branch] | [what this PR contains] | None |
| 2  | [repo]     | [branch] | [what this PR contains] | PR 1 merged |
| ...| ...        | ...    | ...         | ...          |

[If all changes fit in a single PR, use one row. For multi-repo tasks, list PRs in merge order. Note which can be reviewed in parallel.]

## Verification

[End-to-end verification mapped to the spec's acceptance criteria.]

- [Acceptance criterion] - [how to verify]
- ...

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| [What could go wrong] | [What breaks] | [How to prevent or recover] |
| ...  | ...    | ...        |
```

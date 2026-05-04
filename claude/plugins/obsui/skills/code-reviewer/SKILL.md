---
name: code-reviewer
description: Code review a PR using parallel agents for multi-angle analysis
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh pr list:*), Bash(git log:*), Bash(git blame:*)
---

Review a pull request or local commits from multiple angles using parallel agents.

## Input

$ARGUMENTS should be a PR number, GitHub PR URL or number of commits from HEAD to review locally. Extract the PR number from the URL if needed.

Examples:

- `/code-reviewer review the PR 345`
- `/code-reviewer review the changes from the last 5 commits`

## Steps

### 1. Gather PR or local changes context

Run these commands and store the results for agent prompts:

#### For PR

```bash
# Get PR metadata (title, body, files, base branch)
gh pr view <PR_NUMBER> --json title,body,baseRefName,headRefName,commits,files,additions,deletions

# Get the full diff
gh pr diff <PR_NUMBER>
```

#### For Local

```bash
# Get the last N commits from HEAD
git log -n <N> --pretty=format:"%H%n%s%n%b%n"   
# Get the diff for those commits
git diff HEAD~<N> HEAD
```

Read the full contents of every file listed in the `files` array from the PR or local commits metadata. These file contents, together with the diff,
form the review corpus.

Also read the following project config files if they exist (do not fail if missing):

- `CLAUDE.md` (project coding standards and conventions)
- `tsconfig.json` or `tsconfig.*.json` (TypeScript configuration)
- `.eslintrc.*` / `eslint.config.*` (linting rules)
- `package.json` (dependencies, scripts)

### 1b. LSP enrichment (optional)

If LSP is available for the changed file types, gather structured context to include in the Opus lead agent's prompt. If LSP is unavailable for a file
type, skip it — the review proceeds with text-based analysis only.

For each changed file, run these LSP operations on exported symbols that were modified, removed, or had signature changes:

- **`hover`** on modified exported functions/types — capture resolved type signatures
- **`findReferences`** on removed or signature-changed exports — capture reference count and calling files
- **`incomingCalls`** on modified functions — capture callers to assess blast radius

Format the results as a `## LSP Context` section to include in the Opus lead prompt:

```
## LSP Context

### Modified exports
- `functionName` (file.ts:42) — type: `(arg: Foo) => Promise<Bar>`, 8 references across 5 files
- `ComponentName` (Component.tsx:10) — type: `React.FC<Props>`, 3 references

### Removed/renamed exports
- `oldFunction` (file.ts) — had 12 references in: handler.go, service.go, api_test.go

### Call hierarchy (high-risk)
- `processData` (processor.go:88) — called by: handleRequest, batchJob, cronTask
```

If no LSP data is available, omit this section entirely. All agents must treat LSP context as supplementary — its absence does not change the review
approach.

### 2. Two-phase review

**Severity rubric** — all agents must use these definitions:

- **Critical:** Data loss, security exploit, crash, or silent data corruption. Would block merge.
- **Important:** Incorrect behavior, missing error handling, or regression that affects users. Should be fixed before merge.
- **Nit:** Improvement opportunity — cleaner pattern, better naming, minor edge case. Optional to address.

**Findings format** — all agents must use this structure. If no issues are found, return "No issues found."

```
## Findings

### [Critical|Important|Nit] — <short title>
- **File:** <path>:<line>
- **Detail:** <what is wrong and why it matters>
- **Suggestion:** <how to fix>
```

#### 2a. Phase 1 — Lead review (Opus)

Launch **1 agent** with `model: "opus"`. It receives the full PR context (title, description, commits, diff, full file contents, any relevant project
conventions from config files read in Step 1, and the LSP Context section from Step 1b if available). It has a dual mandate:

**Mandate A — Bugs & Security findings:**

Review the diff and full file context for correctness and security issues:

- **Correctness:** logic errors, null/undefined dereferences, uninitialized variables, React hooks violations (rules of hooks, incorrect useEffect
  dependency arrays, state updates after unmount)
- **Type safety:** `any` abuse, unsafe type assertions (`as`), missing return types on exported functions, incorrect generics
- **Resource management:** unclosed handles/connections, uncleared timers/intervals, orphaned subscriptions or listeners, unhandled promise
  rejections, swallowed errors
- **Race conditions:** shared mutable state, unsynchronized async operations, stale closures over mutable values
- **Injection & output encoding:** XSS (`dangerouslySetInnerHTML`, unsanitized DOM input), `eval()`/`new Function()`, SQL/command injection, path
  traversal, SSRF, unvalidated URL redirects
- **Secrets & crypto:** hardcoded credentials in code/config/client bundles, insecure client-side storage, TLS/crypto misconfiguration, missing CSRF
  protections

Use LSP Context (if provided) to verify type signatures, reference counts, and blast radius rather than inferring from raw text. Focus on real bugs
and vulnerabilities introduced or worsened by this PR. Ignore style, naming, formatting, and pre-existing issues.

**Mandate B — Scoped briefing and routing decision:**

After producing findings, append a `## Briefing` section:

- **Tech stack:** detected languages and frameworks from file extensions and imports. Classify as one of: `frontend-only`, `backend-only`, or `mixed`.
  This determines which agents launch in Phase 2.
- **Summary:** 2-3 sentences on what the PR does and its stated intent
- **High-risk areas:** files or code paths with the most complexity or change density. Incorporate LSP `incomingCalls` data when available (e.g.,
  "this function is called from 12 places").
- **Performance concerns:** unnecessary re-renders, missing memoization, expensive operations in hot paths, bundle size impact from new dependencies
- **Test review hints:** areas where test coverage seems thin or edge cases matter most
- **Alignment hints:** concerns about scope creep, missing pieces, or potential breaking changes

The Briefing section is always required, even if Findings says "No issues found."

#### 2b. Phase 2 — Scoped reviews (Sonnet, parallel)

After Phase 1 completes, read the **Tech stack** field from the briefing and launch the appropriate agents in a **single message** with
`model: "sonnet"`. Each receives the full diff, full file contents, the lead agent's **Briefing** section (not its findings), relevant project
conventions from Step 1, and its mandate.

**Routing:**

| Tech stack      | Agents launched                                        |
| --------------- | ------------------------------------------------------ |
| `frontend-only` | Agent A-Frontend + Agent B                             |
| `backend-only`  | Agent A-Backend + Agent B                              |
| `mixed`         | Agent A-Frontend + Agent A-Backend + Agent B + Agent C |

##### Agent A-Frontend — Test Quality (Frontend)

Review test files for frontend (TypeScript/React/JS) code changes. Use the lead agent's **Test review hints** to prioritize.

- **Ineffective tests:** tests that don't exercise changed code paths, would pass if the feature were broken, or only assert non-null/non-undefined
  without verifying behavior
- **Missing edge case coverage** for new functionality
- **Component testing:** components not tested for rendering, interactions, and edge states (loading, error, empty); tests coupled to implementation
  details instead of observable behavior
- **Low-value or missing assertions:** overly broad snapshot tests, missing accessibility assertions (roles, labels, focus management)
- **Mock realism:** API/service mocks that don't match actual contracts or realistic conditions
- **Project conventions:** adherence to existing test patterns, CLAUDE.md standards, and project documentation

##### Agent A-Backend — Test Quality (Backend)

Review test files for backend (Go/Python/Java/etc.) code changes. Use the lead agent's **Test review hints** to prioritize.

- **Ineffective tests:** tests that don't exercise changed code paths, would pass if the feature were broken, or only assert err == nil without
  verifying behavior
- **Missing edge case coverage** for new functionality
- **Integration tests:** critical paths tested against real dependencies (databases, APIs) rather than only mocks; test fixtures that reflect
  production data shapes
- **Table-driven tests:** parameterized tests for functions with multiple input/output combinations rather than duplicated test bodies
- **Error path coverage:** error conditions, timeouts, retries, and graceful degradation tested, not just the happy path
- **Project conventions:** adherence to existing test patterns, CLAUDE.md standards, and project documentation

##### Agent B — Feature Alignment & Compatibility

Review the PR holistically against its stated purpose. Use the lead agent's **Alignment hints** and **Summary** for context.

- **Scope and intent match:** does the implementation match the PR title, description, and linked issues without unrelated changes or missing pieces?
- **Breaking changes:** removed/renamed public APIs, exported functions, interfaces, component props (new required props, changed types), or config
  fields (YAML, JSON, Helm, CRDs, package.json, tsconfig) without migration path
- **API version changes** and their implications for existing consumers
- **Accessibility regressions:** removed aria attributes, broken keyboard navigation, missing focus management
- **Performance regressions:** new expensive operations in hot paths, increased bundle size from dependencies, inefficient algorithms
- **Component or modules reuses and coupling:** new code that tightly couples previously independent modules or components, making future changes
  harder or it does not reuse existing code where it would be appropriate
- **Undocumented behavior changes:** silent UX/behavior regressions or changes not called out in the PR description
- **Breaking change documentation:** are breaking changes explicitly noted?
- **New dependencies:** justified, no overlap with existing packages, compatible licenses, reasonable bundle size impact

##### Agent C — Cross-boundary consistency (mixed PRs only)

Only launched when Tech stack is `mixed`. Review whether frontend and backend changes are consistent with each other.

- **API contract alignment:** do request/response shapes, field names, types, and status codes match between backend handlers and frontend API calls?
- **Shared types/schemas:** if the project has shared type definitions (OpenAPI, protobuf, GraphQL, shared TS types), are they updated and do both
  sides conform?
- **Error handling consistency:** do frontend components handle all error codes/shapes the backend can return? Are new backend error cases surfaced in
  the UI?
- **Feature flag parity:** if a feature is gated on one side, is it gated on the other?
- **Deployment ordering:** would deploying backend before frontend (or vice versa) break anything? Flag changes that require coordinated deployment.

### 3. Synthesize findings

After all agents return:

1. Collect all findings from the lead agent (Phase 1) and all scoped agents (Phase 2)
2. Deduplicate — if multiple agents flagged the same issue, merge into one entry and note which perspectives caught it
3. Sort by severity: Critical first, then Important, then Nit
4. Drop false positives using these criteria:
   - The issue exists in unchanged code and the PR doesn't make it worse
   - The finding is purely stylistic and would be caught by a linter or formatter
   - The finding contradicts an explicit project convention from CLAUDE.md or config files
   - The suggestion is speculative ("might cause issues") without a concrete scenario

### 4. Present the review

Output the final review in this format:

```markdown
## PR Review: <PR title>

**PR:** #<number> | **Files changed:** <count> | **+<additions> / -<deletions>**

### Critical

<numbered list of critical issues, or "None">

### Important

<numbered list of important issues, or "None">

### Nits

<numbered list of nits, or "None">

### What looks good

<2-3 bullet points on things done well>
```

Do not auto-comment on the PR. Present the review in the conversation so the user can curate it before posting.

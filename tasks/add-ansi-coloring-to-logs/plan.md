# Plan: Add ANSI Color Parsing to Logs Table Plugin

## Problem

The Perses logs table plugin renders log messages as plain text, meaning ANSI escape sequences (e.g., `\x1b[31mERROR\x1b[0m`) appear as raw garbage
characters instead of colored text. Many logging frameworks (Go's `slog`, Node's `pino`, Python's `logging`) emit ANSI-colored output. Without parsing
these codes, the logs table displays unreadable escape sequences where users expect colored severity indicators, highlighted values, and structured
output.

## Current State

| Component                   | File / Location                                        | Current Behavior                                                                                                                          |
| --------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Log text rendering          | `logstable/src/components/LogRow/LogRow.tsx:197-199`   | Renders `{log.line}` as plain text children of `LogText` Typography component. ANSI escape sequences appear as raw characters.            |
| LogText styled component    | `logstable/src/components/LogRow/LogsStyles.tsx:61-79` | MUI `Typography` styled component with monospace font, `allowWrap` prop. No HTML rendering support.                                       |
| Copy helpers                | `logstable/src/utils/copyHelpers.ts:53-55`             | `formatLogMessage()` returns `log.line` verbatim, meaning copied text includes raw ANSI escape sequences.                                 |
| Markdown plugin (reference) | `markdown/src/MarkdownPanel.tsx:74-76,92`              | Uses `DOMPurify.sanitize()` + `dangerouslySetInnerHTML` pattern. DOMPurify is already a dependency in the monorepo (`dompurify: ^3.2.3`). |

## Changes

### Phase 1: Add Dependencies and Create ANSI Utility

**Dependency:** None **Parallel with:** None

#### Files Modified

| File                          | Change                                                         |
| ----------------------------- | -------------------------------------------------------------- |
| `logstable/package.json`      | Add `ansi_up` and `dompurify` as dependencies                  |
| `logstable/src/utils/ansi.ts` | **New file.** ANSI-to-HTML conversion and sanitization utility |

#### Details

**Add dependencies to `logstable/package.json`:**

```json
"dependencies": {
  "ansi_up": "^6.0.0",
  "dompurify": "^3.2.3"
}
```

`ansi_up` is chosen because:

- Built-in XSS escaping (escapes HTML entities before processing ANSI codes)
- Supports `use_classes = true` for CSS class-based output (required for dark mode theming)
- Handles 8/16 standard colors via class names, 256-color and truecolor via inline styles
- Small bundle (~5KB minified), no dependencies
- Well-maintained, widely used

`dompurify` is already used by the markdown plugin in this monorepo, so it's a known/approved dependency.

**Create `logstable/src/utils/ansi.ts`:**

```typescript
import AnsiUp from 'ansi_up';
import DOMPurify from 'dompurify';

const ansiUp = new AnsiUp();
ansiUp.use_classes = true;

const ANSI_REGEX = /\x1b\[/;

export function ansiToSanitizedHtml(text: string): string | null {
  if (!ANSI_REGEX.test(text)) {
    return null;
  }
  const html = ansiUp.ansi_to_html(text);
  return DOMPurify.sanitize(html, {
    ALLOWED_TAGS: ['span'],
    ALLOWED_ATTR: ['class', 'style'],
  });
}

const ANSI_STRIP_REGEX = /\x1b\[[0-9;]*m/g;

export function stripAnsi(text: string): string {
  return text.replace(ANSI_STRIP_REGEX, '');
}
```

Key design decisions:

- **Early return for non-ANSI text:** The fast `ANSI_REGEX` check avoids running the parser and sanitizer on plain text (the vast majority of log
  lines). Returns `null` to signal the caller should render as plain text.
- **Singleton `AnsiUp` instance:** `use_classes = true` is set once. The instance is stateless between calls.
- **DOMPurify whitelist:** Only `<span>` tags with `class` and `style` attributes are allowed. `class` handles the standard 16 ANSI colors; `style`
  handles 256-color/truecolor where `ansi_up` must use inline `color:` properties. All other HTML is stripped.
- **`stripAnsi` function:** Removes ANSI escape sequences for copy-to-clipboard, so users get clean plain text.

#### Phase 1 Verification

- `npm install` in `logstable/` resolves without errors
- `npx tsc --noEmit` passes with the new utility file
- Manual check: import `ansiToSanitizedHtml` in a test and verify output for `"\x1b[31mERROR\x1b[0m"` produces
  `<span class="ansi-red-fg">ERROR</span>`

---

### Phase 2: Add Theme-Aware ANSI Color Styles via CSS

**Dependency:** None **Parallel with:** Phase 1 (no file overlap)

#### Files Modified

| File                                             | Change                                                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `logstable/src/components/LogRow/ansiColors.css` | **New file.** Pure CSS defining ANSI color classes via custom properties with light/dark mode variants |
| `logstable/src/components/LogRow/LogRow.tsx`     | Import the CSS file                                                                                    |

#### Details

Instead of coupling color definitions to the `LogText` styled component via a JS function, define ANSI colors in a standalone CSS file using CSS
custom properties. This makes colors overridable via standard CSS specificity — consumers or theme integrations can redefine the custom properties
without touching component code.

**Create `logstable/src/components/LogRow/ansiColors.css`:**

`ansi_up` with `use_classes = true` generates spans with class names following this pattern:

- Foreground: `ansi-black-fg`, `ansi-red-fg`, `ansi-green-fg`, `ansi-yellow-fg`, `ansi-blue-fg`, `ansi-magenta-fg`, `ansi-cyan-fg`, `ansi-white-fg`
- Bright foreground: `ansi-bright-black-fg`, `ansi-bright-red-fg`, etc.
- Background: `ansi-black-bg`, `ansi-red-bg`, etc.
- Bold: `ansi-bold`

```css
/* Light mode defaults */
:root {
  --ansi-black:          #000000;
  --ansi-red:            #cc0000;
  --ansi-green:          #00aa00;
  --ansi-yellow:         #aa5500;
  --ansi-blue:           #0000aa;
  --ansi-magenta:        #aa00aa;
  --ansi-cyan:           #00aaaa;
  --ansi-white:          #aaaaaa;
  --ansi-bright-black:   #555555;
  --ansi-bright-red:     #ff5555;
  --ansi-bright-green:   #55ff55;
  --ansi-bright-yellow:  #ffff55;
  --ansi-bright-blue:    #5555ff;
  --ansi-bright-magenta: #ff55ff;
  --ansi-bright-cyan:    #55ffff;
  --ansi-bright-white:   #ffffff;
}

/* Dark mode overrides — MUI sets [data-mui-color-scheme="dark"] on the root,
   falling back to OS preference via prefers-color-scheme */
[data-mui-color-scheme="dark"],
.dark-mode {
  --ansi-black:          #555555;
  --ansi-red:            #ff6b6b;
  --ansi-green:          #69db7c;
  --ansi-yellow:         #ffd43b;
  --ansi-blue:           #74c0fc;
  --ansi-magenta:        #da77f2;
  --ansi-cyan:           #66d9e8;
  --ansi-white:          #ffffff;
  --ansi-bright-black:   #888888;
  --ansi-bright-red:     #ff8787;
  --ansi-bright-green:   #8ce99a;
  --ansi-bright-yellow:  #ffe066;
  --ansi-bright-blue:    #a5d8ff;
  --ansi-bright-magenta: #e599f7;
  --ansi-bright-cyan:    #99e9f2;
  --ansi-bright-white:   #ffffff;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-mui-color-scheme="light"]) {
    --ansi-black:          #555555;
    --ansi-red:            #ff6b6b;
    --ansi-green:          #69db7c;
    --ansi-yellow:         #ffd43b;
    --ansi-blue:           #74c0fc;
    --ansi-magenta:        #da77f2;
    --ansi-cyan:           #66d9e8;
    --ansi-white:          #ffffff;
    --ansi-bright-black:   #888888;
    --ansi-bright-red:     #ff8787;
    --ansi-bright-green:   #8ce99a;
    --ansi-bright-yellow:  #ffe066;
    --ansi-bright-blue:    #a5d8ff;
    --ansi-bright-magenta: #e599f7;
    --ansi-bright-cyan:    #99e9f2;
    --ansi-bright-white:   #ffffff;
  }
}

/* Foreground colors */
.ansi-black-fg          { color: var(--ansi-black); }
.ansi-red-fg            { color: var(--ansi-red); }
.ansi-green-fg          { color: var(--ansi-green); }
.ansi-yellow-fg         { color: var(--ansi-yellow); }
.ansi-blue-fg           { color: var(--ansi-blue); }
.ansi-magenta-fg        { color: var(--ansi-magenta); }
.ansi-cyan-fg           { color: var(--ansi-cyan); }
.ansi-white-fg          { color: var(--ansi-white); }
.ansi-bright-black-fg   { color: var(--ansi-bright-black); }
.ansi-bright-red-fg     { color: var(--ansi-bright-red); }
.ansi-bright-green-fg   { color: var(--ansi-bright-green); }
.ansi-bright-yellow-fg  { color: var(--ansi-bright-yellow); }
.ansi-bright-blue-fg    { color: var(--ansi-bright-blue); }
.ansi-bright-magenta-fg { color: var(--ansi-bright-magenta); }
.ansi-bright-cyan-fg    { color: var(--ansi-bright-cyan); }
.ansi-bright-white-fg   { color: var(--ansi-bright-white); }

/* Background colors */
.ansi-black-bg          { background-color: var(--ansi-black); }
.ansi-red-bg            { background-color: var(--ansi-red); }
.ansi-green-bg          { background-color: var(--ansi-green); }
.ansi-yellow-bg         { background-color: var(--ansi-yellow); }
.ansi-blue-bg           { background-color: var(--ansi-blue); }
.ansi-magenta-bg        { background-color: var(--ansi-magenta); }
.ansi-cyan-bg           { background-color: var(--ansi-cyan); }
.ansi-white-bg          { background-color: var(--ansi-white); }

/* Text decoration */
.ansi-bold              { font-weight: bold; }
```

**Design rationale:**

- **CSS custom properties** (`--ansi-*`) allow overriding colors without touching the CSS file. A consuming application can redefine `--ansi-red` at
  any specificity level to change the red color globally.
- **Three dark mode selectors** provide maximum compatibility:
  1. `[data-mui-color-scheme="dark"]` — MUI v5+ CSS vars theme sets this on the root element
  2. `.dark-mode` — generic fallback for apps that use a class-based dark mode toggle
  3. `@media (prefers-color-scheme: dark)` — OS-level preference, guarded by `:not([data-mui-color-scheme="light"])` so explicit MUI light mode wins
- **No coupling to LogText or LogsStyles.tsx** — the `LogText` styled component is unchanged. The ANSI classes are global CSS that apply wherever
  `ansi_up` generates `<span class="ansi-red-fg">` elements, regardless of the parent component.
- **Overridable by consumers** — to change ANSI red in dark mode, a consumer just adds:
  ```css
  [data-mui-color-scheme="dark"] { --ansi-red: #ff4444; }
  ```

**Import in `LogRow.tsx`:**

Add at the top of the file (with other imports):

```typescript
import './ansiColors.css';
```

The RSBuild/webpack bundler already handles `.css` imports in the logstable plugin (same build toolchain as the rest of perses-plugins).

#### Phase 2 Verification

- `npm run build` in `logstable/` — CSS file is included in the bundle
- Visual inspection: open the built CSS output and confirm the custom property definitions and class rules are present
- Verify the CSS file has no syntax errors by loading it in a browser dev tools

---

### Phase 3: Integrate ANSI Rendering into LogRow

**Dependency:** Phase 1, Phase 2 **Parallel with:** None

#### Files Modified

| File                                         | Change                                                                                            |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `logstable/src/components/LogRow/LogRow.tsx` | Use `ansiToSanitizedHtml` to render log text as colored HTML; use `stripAnsi` for copy operations |
| `logstable/src/utils/copyHelpers.ts`         | Strip ANSI codes in `formatLogMessage` and `formatLogEntry` so copied text is clean               |

#### Details

##### LogRow.tsx changes

At the top of the file, add import:

```typescript
import { ansiToSanitizedHtml } from '../../utils/ansi';
```

Inside the `DefaultLogRow` component (after line 67), add a memoized ANSI conversion:

```typescript
const ansiHtml = useMemo(
  () => (log ? ansiToSanitizedHtml(log.line) : null),
  [log]
);
```

Add `useMemo` to the React import on line 14.

Replace the rendering at lines 197-199:

```tsx
// Before:
<LogText variant="body2" allowWrap={allowWrap}>
  {log.line}
</LogText>

// After:
{ansiHtml ? (
  <LogText
    variant="body2"
    allowWrap={allowWrap}
    dangerouslySetInnerHTML={{ __html: ansiHtml }}
  />
) : (
  <LogText variant="body2" allowWrap={allowWrap}>
    {log.line}
  </LogText>
)}
```

This approach:

- **Falls back to plain text** when no ANSI codes are present (`ansiHtml` is `null`), avoiding `dangerouslySetInnerHTML` entirely for clean log lines
- **Memoizes the conversion** so parsing + sanitization only runs when `log` changes, not on every re-render
- **Preserves existing behavior** for non-ANSI logs — no DOM structure change, same React text children

##### copyHelpers.ts changes

Import the strip function:

```typescript
import { stripAnsi } from './ansi';
```

Update `formatLogMessage` (line 53-55) and `formatLogEntry` (line 44-48) to strip ANSI codes:

```typescript
export function formatLogMessage(log: LogEntry): string {
  return stripAnsi(log.line);
}

export function formatLogEntry(log: LogEntry): string {
  const timestamp = formatTimestamp(log.timestamp);
  const labels = formatLabels(log.labels || {});
  const cleanLine = stripAnsi(log.line);
  return labels ? `${timestamp} ${labels} ${cleanLine}` : `${timestamp} ${cleanLine}`;
}
```

Note: `formatLogAsJson` is intentionally left unchanged — JSON copy should preserve the raw `log.line` value including ANSI codes, since JSON is a
data format and consumers may want the original data.

#### Phase 3 Verification

- `npx tsc --noEmit` passes
- `npm test` in `logstable/` — existing tests still pass
- Manual test: create a log entry with `line: "\x1b[31mERROR\x1b[0m connection refused"` and verify the word "ERROR" renders in red while "connection
  refused" renders in the default text color

---

### Phase 4: Testing

**Dependency:** Phase 3 **Parallel with:** None

#### Files Modified

| File                                              | Change                                                             |
| ------------------------------------------------- | ------------------------------------------------------------------ |
| `logstable/src/utils/ansi.test.ts`                | **New file.** Unit tests for `ansiToSanitizedHtml` and `stripAnsi` |
| `logstable/src/components/LogRow/LogRow.test.tsx` | Add tests for ANSI-colored log rendering                           |
| `logstable/src/utils/copyHelpers.test.ts`         | Add tests verifying ANSI codes are stripped from copied text       |

#### Details

##### `ansi.test.ts` — Unit tests for ANSI utility

Test cases:

1. **Plain text passthrough:** `ansiToSanitizedHtml("hello world")` returns `null`
2. **Basic color:** `ansiToSanitizedHtml("\x1b[31mERROR\x1b[0m")` returns HTML containing `<span class="ansi-red-fg">ERROR</span>`
3. **Multiple colors:** Text with multiple ANSI color codes produces correctly nested/sequential spans
4. **256-color codes:** `ansiToSanitizedHtml("\x1b[38;5;196mtext\x1b[0m")` returns HTML with inline `style` attribute
5. **XSS prevention:** `ansiToSanitizedHtml("\x1b[31m<script>alert('xss')</script>\x1b[0m")` returns HTML with script tags stripped — the output
   should contain `&lt;script&gt;` or just the text content, never an executable `<script>` tag
6. **XSS via attributes:** Verify that injected `onload`, `onerror`, and other event handler attributes are stripped
7. **Strip function:** `stripAnsi("\x1b[31mERROR\x1b[0m text")` returns `"ERROR text"`
8. **Strip plain text:** `stripAnsi("no codes here")` returns `"no codes here"`

##### `LogRow.test.tsx` — Component tests for ANSI rendering

Add to the existing test suite:

```typescript
it('should render ANSI colored log text as HTML', () => {
  const ansiLog: LogEntry = {
    timestamp: 1767225600,
    line: '\x1b[31mERROR\x1b[0m connection refused',
    labels: { level: 'error' },
  };
  render(
    <LogRow log={ansiLog} index={0} isExpanded={false} onToggle={jest.fn()} />
  );
  const errorSpan = document.querySelector('.ansi-red-fg');
  expect(errorSpan).toBeInTheDocument();
  expect(errorSpan).toHaveTextContent('ERROR');
});

it('should render plain log text without dangerouslySetInnerHTML', () => {
  renderLogRow(); // uses existing mockLog with plain text
  expect(screen.getByText('foo bar baz')).toBeInTheDocument();
  // Verify no spans with ansi classes were created
  expect(document.querySelector('[class*="ansi-"]')).toBeNull();
});
```

##### `copyHelpers.test.ts` — Tests for ANSI stripping in copy

Add to the existing test suite:

```typescript
it('should strip ANSI codes from log message when copying', () => {
  const ansiLog: LogEntry = {
    timestamp: 1767225600,
    line: '\x1b[31mERROR\x1b[0m connection refused',
    labels: {},
  };
  expect(formatLogMessage(ansiLog)).toBe('ERROR connection refused');
});

it('should strip ANSI codes from full log entry when copying', () => {
  const ansiLog: LogEntry = {
    timestamp: 1767225600,
    line: '\x1b[32mINFO\x1b[0m server started',
    labels: { level: 'info' },
  };
  const result = formatLogEntry(ansiLog);
  expect(result).not.toContain('\x1b[');
  expect(result).toContain('INFO server started');
});

it('should preserve ANSI codes in JSON format', () => {
  const ansiLog: LogEntry = {
    timestamp: 1767225600,
    line: '\x1b[31mERROR\x1b[0m',
    labels: {},
  };
  const result = formatLogAsJson(ansiLog);
  const parsed = JSON.parse(result);
  expect(parsed.line).toBe('\x1b[31mERROR\x1b[0m');
});
```

#### Phase 4 Verification

- `npm test` in `logstable/` — all tests pass (existing + new)
- `npx tsc --noEmit` passes
- Test coverage: verify the ANSI utility tests cover the XSS prevention cases specifically

---

## PR Strategy

| PR | Repository     | Branch                             | Description                                                                                                                             | Dependencies |
| -- | -------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 1  | perses/plugins | `feat/ansi-log-colors` from `main` | Add ANSI color parsing to logs table plugin with theme-aware CSS classes, XSS-safe sanitization, and ANSI stripping for copy operations | None         |

All changes fit in a single PR since they are scoped to the `logstable` plugin within the `perses-plugins` monorepo.

## Verification

End-to-end verification mapped to the spec's acceptance criteria:

- [ ] **ANSI symbols render as colored text** — Create a dashboard with a Loki datasource that returns logs with ANSI color codes. Verify that colored
      text appears correctly in both dark and light themes. Test with: basic 8 colors, bright colors, background colors, and mixed colored/plain text
      on the same line.
- [ ] **No XSS vulnerabilities** — Unit tests verify that `<script>`, event handlers (`onload`, `onerror`), and other HTML injection vectors are
      stripped by DOMPurify. The implementation uses `ALLOWED_TAGS: ['span']` and `ALLOWED_ATTR: ['class', 'style']` whitelist. Plain-text logs (no
      ANSI) bypass `dangerouslySetInnerHTML` entirely.
- [ ] **Various ANSI color codes tested** — Unit tests cover: plain text passthrough, single color, multiple colors, bright colors, 256-color codes,
      reset codes, and mixed ANSI/plain text. Component tests verify the spans render with correct CSS classes in the DOM.
- [ ] **Copy operations produce clean text** — Unit tests verify `formatLogMessage` and `formatLogEntry` strip ANSI codes. `formatLogAsJson` preserves
      raw data.
- [ ] **No regression** — All existing tests continue to pass. Plain-text logs render identically to before (same DOM structure, no
      `dangerouslySetInnerHTML`).

## Risks

| Risk                                                              | Impact                                                       | Mitigation                                                                                                                                                                                              |
| ----------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ansi_up` generates unexpected HTML tags beyond `<span>`          | DOMPurify would strip them, causing visual gaps              | DOMPurify whitelist ensures only `<span>` passes through; `ansi_up` only generates `<span>` tags by design. Pin `ansi_up` major version.                                                                |
| Theme color values don't have sufficient contrast in one mode     | Colored text may be unreadable against certain backgrounds   | Color values are chosen for contrast in both modes. Can be tuned post-merge by overriding `--ansi-*` CSS custom properties. Visual review during PR is essential.                                       |
| Performance impact on large log volumes                           | Parsing + sanitizing thousands of log lines could cause jank | Fast regex check skips non-ANSI lines (vast majority). `useMemo` prevents re-parsing. `AnsiUp` is lightweight (~5KB). If needed, virtualized list already handles rendering.                            |
| `dompurify` version mismatch with markdown plugin                 | Could cause duplicate bundles or type conflicts              | Use same version (`^3.2.3`) as the markdown plugin. Both are direct dependencies in separate workspaces — npm hoists to shared `node_modules`.                                                          |
| 256-color/truecolor ANSI codes use inline styles, not CSS classes | Dark mode theming doesn't apply to inline-styled colors      | Acceptable tradeoff: 256-color/truecolor codes specify exact colors by definition, so theme adaptation isn't expected. Standard 16-color codes (the common case) use classes and are fully theme-aware. |

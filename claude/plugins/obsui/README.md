# obsui — Claude Code Plugin

Development assistant for the observability UI team.

## Skills

| Skill           | Invoke                      | Description                                                |
| --------------- | --------------------------- | ---------------------------------------------------------- |
| `code-reviewer` | `/obsui:code-reviewer <PR>` | Multi-phase PR review using Opus lead + Sonnet specialists |

## Installation

### From the marketplace

Add the repo as a marketplace, then install the plugin:

```bash
/plugin marketplace add observability-ui/harness
/plugin install obsui@harness
```

### From a local path

For development or testing, load the plugin for a single session:

```bash
claude --plugin-dir /path/to/ai-sdlc/claude/plugins/obsui
```

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

The `obsui` plugin and its skills should appear in the list.

## Usage

### Typical workflow

Navigate to the project repo, check out the PR branch locally, then start Claude and run the review:

```bash
# Go to your local clone
cd ~/projects/my-repo

# Fetch and check out the PR branch so files are available locally
gh pr checkout 123

# Start Claude (add --plugin-dir if not installed via marketplace)
claude

# Run the review
/obsui:code-reviewer 123
```

This ensures the skill reads files directly from disk instead of downloading them, and LSP servers can resolve types and references against the full
project.

### Quick review (without checkout)

If you just want a diff-based review without LSP enrichment, you can run from any directory with `gh` access:

```
/obsui:code-reviewer 123
/obsui:code-reviewer https://github.com/org/repo/pull/123
```

### Prerequisites

- `gh` CLI authenticated with access to the target repository
- For LSP enrichment: run from within the project directory with the PR branch checked out

## Development

Edit `skills/code-reviewer/SKILL.md` directly. Changes take effect on the next skill invocation — no restart needed. Run `/reload-plugins` to pick up
structural changes.

### Plugin structure

```
obsui/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest, LSP config
├── skills/
│   └── code-reviewer/
│       └── SKILL.md         # Multi-phase review skill
└── README.md
```

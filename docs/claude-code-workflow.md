# Claude Code Workflow Guide

This document explains how okuban.nvim uses Claude Code for development and how contributors can use the same workflow. Everything described here is checked into the repo and works automatically when you clone/fork it.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Issue-Driven Development](#3-issue-driven-development)
4. [Custom Skills (Slash Commands)](#4-custom-skills-slash-commands)
5. [Custom Agents (Subagents)](#5-custom-agents-subagents)
6. [Hooks (Enforcement)](#6-hooks-enforcement)
7. [Quick Reference](#7-quick-reference)

---

## 1. Overview

> **Fork-friendly**: Everything in this guide is checked into the repo under `CLAUDE.md` and `.claude/`. When you clone or fork, Claude Code picks it all up automatically — no extra setup needed.

---

This project uses a **three-layer system** to keep development organized:

| Layer | Purpose | How it works |
|-------|---------|--------------|
| **CLAUDE.md** | Guidance | Tells Claude the rules (commit format, branch naming, issue tracking) |
| **Skills** | Workflow | Slash commands that automate multi-step procedures (`/start-issue`, `/close-issue`) |
| **Hooks** | Enforcement | Scripts that block bad actions (e.g., commits without issue references) |

All three layers are checked into the repo under `CLAUDE.md` and `.claude/`. When you clone the repo and run Claude Code, everything is available immediately.

---

## 2. Prerequisites

### Required

| Tool | Purpose | Install |
|------|---------|---------|
| [Claude Code](https://claude.ai) | AI-assisted development | `npm install -g @anthropic-ai/claude-code` |
| [GitHub CLI](https://cli.github.com) (`gh`) | Issue/label management, auth | `brew install gh` then `gh auth login` |
| [jq](https://jqlang.github.io/jq/) | JSON parsing in hooks | `brew install jq` (macOS) or `apt install jq` (Linux) |

### Optional (for specific skills)

| Tool | Used by | Install |
|------|---------|---------|
| [StyLua](https://github.com/JohnnyMorganz/StyLua) | `/lua-lint` | `brew install stylua` or `cargo install stylua` |
| [Luacheck](https://github.com/mpeterv/luacheck) | `/lua-lint` | `brew install luacheck` or `luarocks install luacheck` |
| [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | `/nvim-test` | Install via your Neovim plugin manager |

### What happens if tools are missing?

- **`gh` missing** — `/start-issue` and `/close-issue` won't work. The entire project requires `gh`.
- **`jq` missing** — Hooks degrade gracefully: commits are allowed without issue-reference enforcement. Install `jq` for full protection.
- **`stylua`/`luacheck` missing** — `/lua-lint` will tell you how to install them.
- **`plenary.nvim` missing** — `/nvim-test` will fail. Install it via your plugin manager.

### Why three layers?

CLAUDE.md instructions alone can get diluted in long conversations. Hooks provide deterministic enforcement that always runs. Skills standardize workflows so they're done the same way every time.

---

## 3. Issue-Driven Development

**Every piece of work must have a GitHub issue.** This is the fundamental rule.

### The Workflow

```
1. Issue exists (or you create one)
2. /start-issue 42          ← assigns you, creates branch, sets kanban label
3. Write code, commit        ← commits must reference the issue
4. Create PR                 ← PR body includes "Fixes #42"
5. /close-issue 42           ← moves label to done, closes issue
```

### Why?

- Issues are the single source of truth for what's being worked on
- The kanban board (this plugin!) reads from issues — untracked work is invisible
- Git history links back to issue context (the "why" behind changes)
- Contributors can see what's available, in progress, and done

### Commit Message Format

```
<type>(<scope>): <description> (<keyword> #<issue>)
```

**Types**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

**Keywords**:
| Keyword | Effect on merge |
|---------|----------------|
| `Fixes #42` | Auto-closes the issue |
| `Closes #42` | Auto-closes the issue |
| `Resolves #42` | Auto-closes the issue |
| `Refs #42` | Links without closing |

**Examples**:
```
feat(ui): add kanban board column rendering (Fixes #42)
fix(api): handle empty label list in gh response (Fixes #15)
docs(readme): add troubleshooting section (Refs #7)
chore(ci): add StyLua check to GitHub Actions (Refs #30)
```

### Branch Naming

```
<type>/issue-<NUMBER>-<short-description>
```

Examples: `feat/issue-42-board-rendering`, `fix/issue-15-label-sync`, `docs/issue-7-readme`

---

## 4. Custom Skills (Slash Commands)

Skills are reusable workflows invoked with `/command`. They run in your current conversation context and automate multi-step procedures.

### `/start-issue <number>`

Starts work on a GitHub issue. Automates:
1. Fetches and displays issue details
2. Assigns the issue to you
3. Moves the kanban label to `okuban:in-progress`
4. Creates a feature branch (`feat/issue-42-description`)
5. Comments on the issue

**Usage**:
```
/start-issue 42
```

### `/close-issue <number>`

Closes a completed GitHub issue. Automates:
1. Verifies the issue exists and is open
2. Checks for linked PRs
3. Moves the kanban label to `okuban:done`
4. Comments on the issue and closes it

**Usage**:
```
/close-issue 42
```

### `/lua-lint [file]`

Runs StyLua formatting check and Luacheck linting.

**Usage**:
```
/lua-lint                    # Check all Lua files
/lua-lint lua/okuban/api.lua # Check a specific file
```

### `/nvim-test [file]`

Runs plenary.nvim tests in headless Neovim.

**Usage**:
```
/nvim-test                            # Run all tests
/nvim-test tests/test_api_spec.lua    # Run a specific test file
```

### `/gh-graphql [description]`

Tests and explores `gh` CLI commands for issue and label management.

**Usage**:
```
/gh-graphql list issues with label
/gh-graphql move card between columns
```

### How Skills Work

Skills are defined in `.claude/skills/<name>/SKILL.md` files. They use YAML frontmatter for metadata and markdown for instructions. When you type `/skill-name`, Claude reads the SKILL.md and follows its steps.

Key features:
- `$ARGUMENTS` — replaced with whatever you type after the command
- `allowed-tools` — restricts which tools Claude can use
- `disable-model-invocation: true` — only the user can invoke (not auto-triggered)

---

## 5. Custom Agents (Subagents)

Agents are specialized Claude instances that run in **isolated context windows**. They're used for tasks where you want separation from the main conversation.

### `lua-reviewer`

Reviews Lua code for Neovim API best practices and plugin conventions. Read-only — cannot modify files.

**When it's used**: Claude automatically delegates to this agent when code review is needed. You can also ask explicitly: "Use the lua-reviewer agent to review my changes."

### `api-explorer`

Explores and tests GitHub API operations via the `gh` CLI. Can run bash commands to test queries.

**When it's used**: Claude delegates when you need to investigate `gh` CLI behavior or test API commands.

### Skills vs Agents — When to Use Which

| Use a **Skill** when... | Use an **Agent** when... |
|--------------------------|--------------------------|
| You want a repeatable workflow | You need context isolation |
| The task benefits from your chat history | The task should run independently |
| You want a `/slash-command` UX | You want a different model (e.g., Sonnet for speed) |
| Procedural: same steps every time | Exploratory: research, review, investigation |

---

## 6. Hooks (Enforcement)

Hooks are shell scripts that run automatically at specific points in the Claude Code lifecycle. They provide **deterministic enforcement** — they always run, even if Claude forgets the rules.

### `validate-commit-issue-ref.sh` (PreToolUse)

**What it does**: Intercepts every `git commit` command and checks that the commit message references a GitHub issue (`#42`, `Fixes #42`, `Refs #42`, etc.). If no reference is found, the commit is blocked.

**Why**: Ensures every commit is traceable to an issue. Catches mistakes that CLAUDE.md instructions alone might miss.

**Exemptions**: Merge commits and revert commits are allowed without issue references.

### `load-issue-context.sh` (SessionStart)

**What it does**: When a new Claude Code session starts, this hook checks the current git branch name. If it matches the pattern `*/issue-<number>-*`, the hook fetches the issue details from GitHub and injects them into Claude's context.

**Why**: Claude automatically knows which issue you're working on without being told. This means commits and code changes will naturally reference the right issue.

### How Hooks Are Configured

Hooks are wired up in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/validate-commit-issue-ref.sh"
        }]
      }
    ],
    "SessionStart": [
      {
        "hooks": [{
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/load-issue-context.sh"
        }]
      }
    ]
  }
}
```

### Hook Lifecycle

| Event | When it fires | Our hooks |
|-------|--------------|-----------|
| `SessionStart` | New Claude Code session begins | `load-issue-context.sh` — injects issue context |
| `PreToolUse` | Before any tool runs | `validate-commit-issue-ref.sh` — blocks bad commits |

Hooks take effect when a new session starts. If you modify `.claude/settings.json` during a session, restart Claude Code to pick up the changes.

---

## 7. Quick Reference

### Starting work on an issue

```
/start-issue 42
```

This handles everything: fetch, assign, branch, label, comment.

### Committing

```
feat(ui): add column rendering (Fixes #42)
```

The hook will block commits that don't reference an issue.

### Creating a PR

```bash
gh pr create --title "feat(ui): add column rendering" --body "Fixes #42"
```

### Closing an issue

```
/close-issue 42
```

### Running CI checks locally

```bash
make check     # lint + test (same as GitHub Actions)
make lint      # StyLua + Luacheck only
make test      # plenary.nvim tests only
make format    # auto-format with StyLua
```

All PRs must pass CI (lint + test on Neovim stable/nightly) before merging. Branch protection enforces this.

### File locations

```
.claude/
├── settings.json                          # Hook configuration
├── agents/
│   ├── lua-reviewer.md                    # Code review agent
│   └── api-explorer.md                    # API exploration agent
├── skills/
│   ├── start-issue/SKILL.md               # /start-issue
│   ├── close-issue/SKILL.md               # /close-issue
│   ├── nvim-test/SKILL.md                 # /nvim-test
│   ├── gh-graphql/SKILL.md                # /gh-graphql
│   └── lua-lint/SKILL.md                  # /lua-lint
└── hooks/
    ├── validate-commit-issue-ref.sh       # Commit enforcement
    └── load-issue-context.sh              # Issue context injection
```

### Label system

| Label | Kanban Column | Color |
|-------|--------------|-------|
| `okuban:backlog` | Backlog | `#c5def5` |
| `okuban:todo` | Todo | `#0075ca` |
| `okuban:in-progress` | In Progress | `#fbca04` |
| `okuban:review` | Review | `#d4c5f9` |
| `okuban:done` | Done | `#0e8a16` |

### Issue lifecycle

```
Created → okuban:backlog → okuban:todo → okuban:in-progress → okuban:review → okuban:done → Closed
```

# okuban.nvim

[![CI](https://github.com/khwerhahn/okuban.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/khwerhahn/okuban.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-green.svg)](https://neovim.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> 奥 (oku = deep/inner) + kanban — "deep kanban" or "inner board"

A Neovim plugin that turns GitHub issues into an interactive kanban board inside your editor. No GitHub Projects setup required — just issues and labels.

## Status

**Early Development** — Not yet functional. See [Roadmap](#roadmap) below.

## Why?

Existing solutions either:
- Are local file-based kanbans (no GitHub sync)
- Provide GitHub integration but no kanban view (octo.nvim)
- Require a GitHub Projects board to be set up first

okuban.nvim takes a different approach: your issues **are** your board. Add labels, open Neovim, and you have a kanban.

## How It Works

Issues are sorted into columns based on labels. The plugin ships with an opinionated default label set (fully configurable):

| Label | Column | Color |
|-------|--------|-------|
| `okuban:backlog` | Backlog | `#c5def5` light blue |
| `okuban:todo` | Todo | `#0075ca` blue |
| `okuban:in-progress` | In Progress | `#fbca04` yellow |
| `okuban:review` | Review | `#d4c5f9` lavender |
| `okuban:done` | Done | `#0e8a16` green |

Issues without an `okuban:` label appear in an **Unsorted** column.

Moving a card between columns swaps labels automatically. No GitHub Projects board needed.

## Prerequisites

- Neovim 0.10+
- [GitHub CLI](https://cli.github.com) (`gh`) — installed and authenticated
- [jq](https://jqlang.github.io/jq/) — for Claude Code hook enforcement (`brew install jq`)
- [Claude Code](https://claude.ai) (`claude`) — optional, only for autonomous coding feature

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "khwerhahn/okuban.nvim",
  cmd = { "Okuban", "OkubanSetup" },
  opts = {},
}
```

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'khwerhahn/okuban.nvim'
```

## Quick Start

```vim
" 1. Create kanban column labels on your repo (one-time)
:OkubanSetup

" 1b. (Optional) Also create type, priority, and community labels
:OkubanSetup --full

" 2. Open the kanban board
:Okuban
```

## Configuration

```lua
require("okuban").setup({
  -- Label-to-column mapping (order = left-to-right on the board)
  columns = {
    { label = "okuban:backlog",     name = "Backlog",     color = "#c5def5" },
    { label = "okuban:todo",        name = "Todo",        color = "#0075ca" },
    { label = "okuban:in-progress", name = "In Progress", color = "#fbca04" },
    { label = "okuban:review",      name = "Review",      color = "#d4c5f9" },
    { label = "okuban:done",        name = "Done",        color = "#0e8a16" },
  },

  -- Show a column for issues without any okuban: label
  show_unsorted = true,

  -- Skip preflight checks (for users who know their setup works)
  skip_preflight = false,

  -- GitHub hostname (for Enterprise Server users)
  github_hostname = nil,

  -- Claude Code settings (optional)
  claude = {
    enabled = true,
    max_budget_usd = 5.00,
    max_turns = 30,
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:Okuban` | Open kanban board for the current repo |
| `:OkubanSetup` | Create kanban column labels on the repo |
| `:OkubanSetup --full` | Create kanban + type + priority + community labels |
| `:OkubanRefresh` | Refresh the current board |
| `:OkubanClose` | Close the kanban overlay |

## Keybindings

### Board Navigation

| Key | Action |
|-----|--------|
| `h` / `l` | Move between columns |
| `j` / `k` | Move between cards |
| `<CR>` | Open action menu on selected card |
| `m` | Move card to another column |
| `n` | New draft issue |
| `r` | Refresh board |
| `g` | Jump to auto-detected current issue |
| `q` | Close board |
| `?` | Show help |

### Action Menu

| Key | Action |
|-----|--------|
| `a` | View issue in browser |
| `b` | Close issue (with confirmation) |
| `c` | Code autonomously (worktree + Claude) |
| `<Esc>` / `q` | Dismiss menu |

## Label Setup

Run `:OkubanSetup` to create the 5 kanban column labels. Run `:OkubanSetup --full` to also create type, priority, and community labels.

See [docs/label-setup.md](docs/label-setup.md) for the full label reference with colors, descriptions, and manual `gh label create` commands.

## Roadmap

### Beta — Core Board (label-based)
- [ ] Preflight checks (gh auth, repo scope)
- [ ] `:OkubanSetup` to create default labels
- [ ] Fetch issues per label column via `gh issue list`
- [ ] Multi-column floating window layout with sticky headers
- [ ] Semantic hjkl navigation between columns and cards
- [ ] Move cards between columns (label swap via `gh issue edit`)

### Beta — Smart Features
- [ ] Auto-focus on current issue from git branch/commit context
- [ ] Worktree status indicators per card (exists, dirty, active, ahead/behind)
- [ ] Action menu on cards (view in browser, close, code)
- [ ] Card detail view (issue body, comments, labels)

### Beta — Autonomous Coding
- [ ] Launch Claude Code sessions from the board
- [ ] Git worktree creation and management for isolated coding
- [ ] Monitor running Claude sessions with live status

### Beta — Polish & Community
- [ ] Telescope integration for repo picker
- [ ] Customizable colors and highlight groups
- [ ] Status line integration
- [x] GitHub Actions CI (tests, StyLua, Luacheck)
- [ ] Issue templates, PR template, CONTRIBUTING.md

### v1.0 — GitHub Projects v2
- [ ] GitHub Projects v2 as an alternative/additional data source (GraphQL API)
- [ ] Custom field support (priority, iteration, size)
- [ ] Sync between labels and project board columns

## Development

### Running locally

```bash
# Run tests
make test

# Run lint (StyLua + Luacheck)
make lint

# Run both (same as CI)
make check

# Auto-format with StyLua
make format
```

### CI

Every push to `main` and every PR runs:
- **StyLua** formatting check
- **Luacheck** linting
- **plenary.nvim tests** on Neovim stable + nightly
- **PR title lint** — must follow [Conventional Commits](https://www.conventionalcommits.org/) format

Branch protection requires all checks to pass before merging.

### Releases

Versioning follows [SemVer](https://semver.org/) with `v`-prefixed tags. [release-please](https://github.com/googleapis/release-please) automates version bumps and changelogs based on Conventional Commits.

On each release:
- A `v*` tag and GitHub Release are created automatically
- The `stable` tag is updated (for `version = "*"` in lazy.nvim)
- The plugin is published to [LuaRocks](https://luarocks.org/)

## Contributing with Claude Code

This project is built with Claude Code and ships with a complete AI-assisted development workflow. When you clone or fork the repo, you get:

**Custom skills** (slash commands):
| Command | What it does |
|---------|-------------|
| `/start-issue 42` | Assigns the issue, creates a branch, sets the kanban label, comments |
| `/close-issue 42` | Moves label to done, comments, closes the issue |
| `/lua-lint` | Runs StyLua + Luacheck on the codebase |
| `/nvim-test` | Runs plenary.nvim tests in headless mode |

**Enforcement hooks** (automatic):
- Commits without an issue reference (`Fixes #42`, `Refs #42`) are **blocked**
- Session start auto-detects which issue you're working on from the branch name

**Issue-driven development** — all work must have a GitHub issue:
```
/start-issue 42              # Begin work (branch, assign, label)
# ... write code ...
git commit -m "feat(ui): add board rendering (Fixes #42)"
gh pr create --body "Fixes #42"
/close-issue 42              # Done (label, comment, close)
```

See [docs/claude-code-workflow.md](docs/claude-code-workflow.md) for the full guide.

## Troubleshooting

**"gh CLI not found"**
Install from https://cli.github.com, then run `gh auth login`.

**"Not authenticated with GitHub"**
Run `gh auth login` and follow the prompts.

**"Labels not showing up"**
Run `:OkubanSetup` to create the default labels, then assign them to your issues.

**"Claude Code not available"**
Install Claude Code from https://claude.ai. This is optional — the board works fully without it.

## Design Docs

- [Feature Architecture](docs/feature-architecture.md) — Detailed design for all core features
- [Label Setup](docs/label-setup.md) — Full label reference with colors, descriptions, and `gh` commands
- [Claude Code Workflow](docs/claude-code-workflow.md) — How to use Claude Code with this project: skills, hooks, issue-driven development

## License

MIT

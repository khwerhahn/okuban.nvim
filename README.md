<div align="center">
  <img src="assets/logo.png" alt="okuban.nvim logo" width="200">

  # okuban.nvim

  [![CI](https://github.com/khwerhahn/okuban.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/khwerhahn/okuban.nvim/actions/workflows/ci.yml)
  [![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-green.svg)](https://neovim.io)
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

  > 奥 (oku = deep/inner) + kanban — "deep kanban" or "inner board"
</div>

A Neovim plugin that turns GitHub issues into an interactive kanban board inside your editor. No GitHub Projects setup required — just issues and labels.

## Status

**Beta** — Actively developed. Core features are functional. See [Roadmap](#roadmap) for what's shipped and what's coming.

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

## Features

- **Preview pane** — Issue details (title, labels, assignees, body excerpt) displayed below the board. Automatically updates as you navigate between cards.
- **Auto-polling** — The board refreshes from GitHub every 20 seconds (configurable, or disable with `poll_interval = 0`).
- **Auto-focus** — On board open, okuban detects which issue you're working on from your git branch name, recent commit messages, or the `gh` CLI, and scrolls to that card. Press `g` to re-trigger.
- **Worktree status badges** — Cards show git worktree indicators: `○` (worktree exists, clean), `●` (worktree exists, dirty). The card for your active worktree is highlighted in orange.
- **Action menu** — Press `<CR>` on any card to open a floating menu with actions: move, view in browser, close, assign, or launch Claude Code.
- **Claude Code integration** — Launch autonomous Claude Code sessions directly from the board. Each session runs in its own git worktree with sandboxed tools and budget limits.

## Prerequisites

- Neovim 0.10+
- [GitHub CLI](https://cli.github.com) (`gh`) — installed and authenticated
- [Claude Code](https://claude.ai/code) (`claude`) — optional, only for autonomous coding feature

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "khwerhahn/okuban.nvim",
  cmd = { "Okuban", "OkubanSetup", "OkubanSource", "OkubanMigrate" },
  opts = {},
}
```

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'khwerhahn/okuban.nvim'
```

### Suggested Keymaps

okuban.nvim does not set any global keymaps. Add these to your config if you'd like quick access:

```lua
vim.keymap.set("n", "<leader>ok", "<cmd>Okuban<cr>", { desc = "Open kanban board" })
vim.keymap.set("n", "<leader>oq", "<cmd>OkubanClose<cr>", { desc = "Close kanban board" })
vim.keymap.set("n", "<leader>or", "<cmd>OkubanRefresh<cr>", { desc = "Refresh kanban board" })
vim.keymap.set("n", "<leader>os", "<cmd>OkubanSetup<cr>", { desc = "Create kanban labels" })
vim.keymap.set("n", "<leader>oS", "<cmd>OkubanSetup --full<cr>", { desc = "Create all labels (full)" })
vim.keymap.set("n", "<leader>ol", "<cmd>OkubanSource labels<cr>", { desc = "Switch to label source" })
vim.keymap.set("n", "<leader>op", "<cmd>OkubanSource project<cr>", { desc = "Switch to project source" })
vim.keymap.set("n", "<leader>om", "<cmd>OkubanMigrate project<cr>", { desc = "Migrate labels to project" })
```

Or with lazy.nvim `keys`:

```lua
{
  "khwerhahn/okuban.nvim",
  cmd = { "Okuban", "OkubanSetup", "OkubanSource", "OkubanMigrate" },
  keys = {
    { "<leader>ok", "<cmd>Okuban<cr>", desc = "Open kanban board" },
    { "<leader>oq", "<cmd>OkubanClose<cr>", desc = "Close kanban board" },
    { "<leader>or", "<cmd>OkubanRefresh<cr>", desc = "Refresh kanban board" },
    { "<leader>os", "<cmd>OkubanSetup<cr>", desc = "Create kanban labels" },
    { "<leader>op", "<cmd>OkubanSource project<cr>", desc = "Switch to project source" },
    { "<leader>ol", "<cmd>OkubanSource labels<cr>", desc = "Switch to label source" },
  },
  opts = {},
}
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

All options with their defaults:

```lua
require("okuban").setup({
  -- Data source: "labels" (default) or "project" (GitHub Projects v2)
  source = "labels",

  -- GitHub Projects v2 settings (only used when source = "project")
  project = {
    number = nil,       -- project number (nil = show picker on first :Okuban)
    owner = nil,        -- project owner (nil = auto-detect from repo)
    done_limit = 20,    -- max items to show per column
  },

  -- Label-to-column mapping (only used when source = "labels")
  -- In project mode, columns are read from the project's Status field
  columns = {
    { label = "okuban:backlog",     name = "Backlog",     color = "#c5def5" },
    { label = "okuban:todo",        name = "Todo",        color = "#0075ca" },
    { label = "okuban:in-progress", name = "In Progress", color = "#fbca04" },
    { label = "okuban:review",      name = "Review",      color = "#d4c5f9" },
    { label = "okuban:done",        name = "Done",        color = "#0e8a16", state = "all", limit = 20 },
  },

  -- Show a column for issues without any okuban: label
  show_unsorted = true,

  -- Skip preflight checks (gh auth, repo scope)
  skip_preflight = false,

  -- GitHub hostname (for GitHub Enterprise Server)
  github_hostname = nil,

  -- Height of the preview pane below the board (0 to disable)
  preview_lines = 8,

  -- Show TLDR excerpt from issue body in the preview pane
  show_tldr = true,

  -- Auto-refresh interval in seconds (0 to disable)
  poll_interval = 20,

  -- Board keymaps (all buffer-local to the board windows)
  keymaps = {
    column_left  = "h",
    column_right = "l",
    card_up      = "k",
    card_down    = "j",
    move_card    = "m",
    open_actions = "<CR>",
    goto_current = "g",
    close        = "q",
    refresh      = "r",
    help         = "?",
  },

  -- Claude Code integration (requires `claude` CLI)
  claude = {
    enabled = true,
    max_budget_usd = 5.00,
    max_turns = 30,
    allowed_tools = {
      "Bash(git:*)",
      "Bash(gh:*)",
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
    },
    worktree_base_dir = nil,  -- nil = auto (../repo-worktrees/)
    auto_push = false,        -- push worktree branch on session complete
    auto_pr = false,          -- create PR on session complete
  },
})
```

The Done column uses `state = "all"` to include closed issues and `limit = 20` to cap how many are fetched (for performance). Both are configurable per column.

### Highlight Groups

All highlight groups use `default = true`, so you can override them in your config:

| Group | Default Link | Used For |
|-------|-------------|----------|
| `OkubanCardFocused` | `CursorLine` | Currently selected card |
| `OkubanColumnHeader` | `Title` | Column header text |
| `OkubanCardActive` | `WarningMsg` | Card with an active git worktree (orange) |

Example override:
```lua
vim.api.nvim_set_hl(0, "OkubanCardFocused", { bg = "#2d3f76" })
vim.api.nvim_set_hl(0, "OkubanCardActive", { fg = "#ff9e64", bold = true })
```

## Commands

| Command | Description |
|---------|-------------|
| `:Okuban` | Open kanban board for the current repo |
| `:OkubanSetup` | Create kanban column labels on the repo |
| `:OkubanSetup --full` | Create kanban + type + priority + community labels |
| `:OkubanRefresh` | Refresh the current board |
| `:OkubanClose` | Close the kanban overlay |
| `:OkubanSource labels` | Switch to label-based board |
| `:OkubanSource project [N]` | Switch to project-based board (picker if no number) |
| `:OkubanMigrate project [N]` | Copy label board positions into a GitHub Project |

## Keybindings

### Board Navigation

All keybindings are buffer-local to the board windows and configurable via the `keymaps` option.

| Key | Action |
|-----|--------|
| `h` / `l` | Move between columns |
| `j` / `k` | Move between cards |
| `<CR>` | Open action menu on selected card |
| `m` | Move card to another column |
| `g` | Jump to auto-detected current issue |
| `r` | Refresh board |
| `q` | Close board |
| `?` | Show help |

### Action Menu

Press `<CR>` on any card to open the action menu:

| Key | Action |
|-----|--------|
| `m` | Move to column |
| `v` | View in browser |
| `c` | Close issue (open issues only) |
| `a` | Assign to me (open issues only) |
| `x` | Code with Claude (open issues, when available) |
| `q` / `<Esc>` | Dismiss menu |

## Label Setup

Run `:OkubanSetup` to create the 5 kanban column labels. Run `:OkubanSetup --full` to also create type, priority, and community labels.

See [docs/label-setup.md](docs/label-setup.md) for the full label reference with colors, descriptions, and manual `gh label create` commands.

## Roadmap

### Phase 1: Core Board
- [x] Preflight checks (gh auth, repo scope)
- [x] `:OkubanSetup` to create default labels
- [x] Fetch issues per label column via `gh issue list`
- [x] Multi-column floating window layout with sticky headers
- [x] Semantic hjkl navigation between columns and cards
- [x] Move cards between columns (label swap via `gh issue edit`)

### Phase 2: Smart Features
- [x] Auto-focus on current issue from git branch/commit context
- [x] Worktree status indicators per card (exists, dirty, active)
- [x] Action menu on cards (view, close, assign, code)
- [x] Preview pane with issue details below the board

### Phase 3: Autonomous Coding
- [x] Launch Claude Code sessions from the board
- [x] Git worktree creation and management for isolated coding
- [x] Monitor running Claude sessions with live status badges

### Phase 4: Polish & Community
- [x] GitHub Actions CI (tests, StyLua, Luacheck)
- [x] Issue templates, PR template, CONTRIBUTING.md

### v1.0: GitHub Projects v2
- [x] GitHub Projects v2 as an alternative data source (GraphQL API)
- [x] `:OkubanSource` command for runtime source switching
- [x] `:OkubanMigrate` command for one-time label→project migration
- [ ] Custom field support (priority, iteration, size) on cards

## FAQ

**Do I need GitHub Projects?**
No. By default, okuban.nvim uses GitHub issue labels as its data source. You only need issues and labels — no Projects board setup required.

If your team already uses a GitHub Project, you can switch to it as the data source with `:OkubanSource project`. Columns are read from the project's Status field instead of labels. See [GitHub Projects v2](#github-projects-v2) below.

**Can I customize the columns?**
Yes. Pass a `columns` table to `setup()` with your own labels, names, and colors:
```lua
require("okuban").setup({
  columns = {
    { label = "status:new",  name = "New",  color = "#c5def5" },
    { label = "status:wip",  name = "WIP",  color = "#fbca04" },
    { label = "status:done", name = "Done", color = "#0e8a16", state = "all", limit = 50 },
  },
})
```

**How does auto-focus work?**
When you open the board, okuban tries to detect which issue you're working on using a three-tier cascade:
1. **Branch name** — Parses patterns like `feat/issue-42-description`, `fix/123-null-check`, or `GH-42-oauth`
2. **Recent commits** — Scans the last 5 commit messages for `#N` references
3. **gh CLI** — Queries for issues assigned to you with the `okuban:in-progress` label

Press `g` at any time to re-run detection and jump to the matched card.

**What are the worktree badges?**
Cards show git worktree status when a linked worktree exists:
- `○` — worktree exists, working tree is clean
- `●` — worktree exists, working tree has uncommitted changes
- Orange highlight — this is your currently active worktree

**How does Claude Code integration work?**
From the action menu (`<CR>` then `x`), okuban creates a separate git worktree for the issue, fetches the issue context, and launches Claude Code with sandboxed tools and a budget cap. The session runs autonomously while you continue working. Session status is shown as badges on cards: `[▶]` running, `[✓]` completed, `[✗]` failed.

**Can I use this with GitHub Enterprise?**
Yes. Set the `github_hostname` option:
```lua
require("okuban").setup({
  github_hostname = "github.mycompany.com",
})
```

**How do I disable auto-polling?**
Set `poll_interval` to 0:
```lua
require("okuban").setup({
  poll_interval = 0,
})
```

**Why is the Done column limited to 20 issues?**
The Done column includes closed issues (`state = "all"`), which can grow large over time. The default `limit = 20` keeps the board responsive. You can change this per column:
```lua
columns = {
  -- ...
  { label = "okuban:done", name = "Done", color = "#0e8a16", state = "all", limit = 100 },
},
```

## GitHub Projects v2

okuban supports GitHub Projects v2 as an alternative data source. Instead of reading labels, the board reads from a project's Status field.

### Upgrade Path

1. **Start with labels** (default, zero config) — run `:OkubanSetup`, use `:Okuban`
2. **Create a GitHub Project** via the web UI, add issues, configure Status columns
3. **Switch to the project** — run `:OkubanSource project` in Neovim, pick your project
4. **Migrate cards** (optional) — run `:OkubanMigrate project` to copy label-based positions into the project
5. **Switch back** any time — run `:OkubanSource labels`

### Requirements

GitHub Projects v2 requires the `project` OAuth scope (not included by default):

```bash
gh auth refresh -s project
```

### Permanent Config

To always use a project as the data source:

```lua
require("okuban").setup({
  source = "project",
  project = {
    number = 1,        -- your project number
    owner = "myorg",   -- user or org that owns the project
  },
})
```

If `number` is `nil`, okuban shows a picker on first open. If `owner` is `nil`, it auto-detects from the git remote.

### How It Works

- Columns come from the project's **Status** field options (the same ones that drive the board view on github.com)
- Moving a card updates the Status field value via `gh project item-edit`
- `:OkubanSetup` only creates labels — it never creates or modifies projects
- Issues, labels, assignees, and body are still read from the issue itself (not project fields)

## Troubleshooting

**"gh CLI not found"**
Install from https://cli.github.com, then run `gh auth login`.

**"Not authenticated with GitHub"**
Run `gh auth login` and follow the prompts.

**"Labels not showing up"**
Run `:OkubanSetup` to create the default labels, then assign them to your issues.

**"GitHub Projects requires additional permissions"**
Run `gh auth refresh -s project` to add the `project` scope. This is only needed when using `source = "project"`.

**"Claude Code not available"**
Install Claude Code from https://claude.ai/code. This is optional — the board works fully without it.

**Board looks wrong after resizing the terminal**
The board automatically repositions on `VimResized`, but if something looks off, press `r` to refresh or reopen with `:Okuban`.

## Development

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development guide.

## Contributing with Claude Code

This project ships with a Claude Code workflow. When you clone or fork the repo, you get:

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

See [docs/claude-code-workflow.md](docs/claude-code-workflow.md) for the full guide.

## Design Docs

- [Feature Architecture](docs/feature-architecture.md) — Detailed design for all core features
- [Label Setup](docs/label-setup.md) — Full label reference with colors, descriptions, and `gh` commands
- [Claude Code Workflow](docs/claude-code-workflow.md) — How to use Claude Code with this project

## License

MIT

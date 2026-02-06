# Contributing to okuban.nvim

Thanks for your interest in contributing! This guide covers everything you need to get started.

## Prerequisites

- **Neovim 0.10+** — [Install instructions](https://github.com/neovim/neovim/blob/master/INSTALL.md)
- **GitHub CLI** (`gh`) — [Install](https://cli.github.com), then `gh auth login`
- **StyLua** — `cargo install stylua` or `brew install stylua`
- **Luacheck** — `luarocks install luacheck` or `brew install luacheck`
- **plenary.nvim** — Installed automatically for tests via `tests/minimal_init.lua`

## Development Setup

```bash
# Clone the repo
git clone https://github.com/khwerhahn/okuban.nvim.git
cd okuban.nvim

# Run the full CI check locally
make check
```

### Makefile Targets

| Command | What it does |
|---------|-------------|
| `make test` | Run plenary.nvim tests (Neovim headless) |
| `make lint` | Run StyLua check + Luacheck |
| `make check` | Run lint + test (same as CI) |
| `make format` | Auto-format with StyLua |

## Code Style

- **Formatter**: StyLua (configured in `.stylua.toml`) — 2-space indent, 120 column width
- **Linter**: Luacheck (configured in `.luacheckrc`) — `vim` is a known global
- **File size limit**: 500 lines maximum per file. If a file approaches this, refactor.
- Run `make lint` before committing to catch issues early.

## Testing

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) with busted-style syntax.

### Running Tests

```bash
# All tests
make test

# Single file
nvim --headless -c "PlenaryBustedFile tests/test_config_spec.lua"
```

### Writing Tests

- Test files go in `tests/` and must end with `_spec.lua`
- Use `describe` / `it` / `before_each` / `after_each` blocks
- Mock `vim.system()` for tests that call external commands (see `tests/helpers.lua`)
- Aim for test-driven development: write tests alongside code

### Test File Index

| File | What it tests |
|------|--------------|
| `test_config_spec.lua` | Config defaults and label system |
| `test_api_spec.lua` | Preflight checks |
| `test_api_fetch_spec.lua` | Fetch, parse, and label creation |
| `test_board_layout_spec.lua` | Layout calculations |
| `test_card_render_spec.lua` | Card formatting and worktree badges |
| `test_navigation_spec.lua` | Navigation state and focus |
| `test_move_spec.lua` | Move command |
| `test_integration_spec.lua` | Full flow integration |
| `test_actions_spec.lua` | Action menu |
| `test_detect_spec.lua` | Issue detection cascade |
| `test_worktree_spec.lua` | Worktree parsing and mapping |
| `test_claude_spec.lua` | Claude module |

## Pull Request Process

### 1. Find or Create an Issue

All work must be tracked through a GitHub issue. Check [existing issues](https://github.com/khwerhahn/okuban.nvim/issues) or create a new one.

### 2. Create a Feature Branch

```bash
git checkout main
git pull
git checkout -b <type>/issue-<NUMBER>-<short-description>
```

Branch naming: `feat/issue-42-board-rendering`, `fix/issue-15-label-sync`, `docs/issue-7-readme`

### 3. Make Your Changes

- Write tests alongside your code
- Run `make check` before committing
- Keep commits focused and atomic

### 4. Commit with Issue Reference

```bash
git commit -m "feat(ui): add board column rendering (Fixes #42)"
```

Format: `<type>(<scope>): <description> (<keyword> #<issue>)`

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

Keywords: `Fixes #N` (auto-closes on merge), `Refs #N` (reference only)

### 5. Push and Open a PR

```bash
git push -u origin <branch-name>
gh pr create
```

- PR title must follow [Conventional Commits](https://www.conventionalcommits.org/) format (enforced in CI)
- PR body must include `Fixes #<NUMBER>` or `Closes #<NUMBER>`

### 6. CI Must Pass

The following checks run on every PR:
- StyLua formatting check
- Luacheck linting
- plenary.nvim tests on Neovim stable + nightly
- PR title lint (conventional commit format)

All checks must pass before the PR can be merged.

## Architecture Overview

```
lua/okuban/
├── init.lua          # Plugin entry point: setup(), open(), close(), refresh()
├── config.lua        # User configuration, defaults, deep merge
├── api.lua           # GitHub operations via gh CLI (preflight, fetch, edit, close)
├── detect.lua        # Issue detection from branch/commits/gh CLI
├── worktree.lua      # Git worktree listing, status checks, mapping
├── claude.lua        # Claude Code session management (launch, track, parse)
├── utils.lua         # Notifications and helper functions
└── ui/
    ├── board.lua     # Kanban board layout, window management, polling
    ├── card.lua      # Card rendering, preview pane content
    ├── navigation.lua # Cursor movement, focus, highlight management
    ├── actions.lua   # Action menu popup (move, view, close, assign, code)
    ├── move.lua      # Column picker for moving cards
    └── help.lua      # Help overlay
```

### Data Flow

1. `init.open()` runs preflight checks via `api.preflight()`
2. `api.fetch_all_columns()` queries `gh issue list` per configured column
3. `board.lua` creates floating windows and renders cards via `card.lua`
4. `navigation.lua` manages cursor state and highlights
5. User actions trigger `api.lua` calls which update labels/state on GitHub
6. Auto-polling re-fetches data and refreshes the board in place

## Issue-Driven Development

This project enforces issue-driven development through three layers:

1. **CLAUDE.md** — Project instructions (guidance)
2. **Hooks** — Automated enforcement (blocks commits without issue refs)
3. **Skills** — Workflow automation (`/start-issue`, `/close-issue`)

If you're using Claude Code, these work automatically. If not, just make sure every commit references an issue number.

## Questions?

Open a [GitHub issue](https://github.com/khwerhahn/okuban.nvim/issues/new) or check the [FAQ in the README](README.md#faq).

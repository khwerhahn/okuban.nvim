# okuban.nvim

A Neovim plugin to display GitHub Projects v2 as an interactive ASCII kanban board.

## Project Scope

### Core Goal
Bring GitHub Projects v2 kanban view into Neovim as a floating/overlay window with full keyboard navigation.

### Project Vision
This is an **open-source community plugin**. The primary goal is personal productivity (Neovim + tmux + Claude Code workflow), but the plugin must be built to attract and retain contributors from the Neovim community. This means:
- **Best-in-class documentation** — README, contributing guide, and inline help must be clear enough that anyone can install, use, and contribute within minutes
- **Low barrier to entry** — First-time contributors should be able to pick up an issue, understand the codebase, and submit a PR without needing to ask questions
- **Community standards** — Follow established Neovim plugin conventions so the project feels familiar to experienced plugin developers

### Target Features (MVP)
1. **Authentication** — Use `gh` CLI for GitHub auth (no custom token management)
2. **Fetch Projects** — Query GitHub Projects v2 via GraphQL API
3. **Render Kanban** — Multi-column floating window layout with sticky headers and independent column scrolling
4. **Navigate** — Semantic hjkl navigation: h/l between columns, j/k between cards
5. **Auto-Focus** — Automatically detect the current issue from git context and scroll to it on board open
6. **Card Actions** — Press a key on any card to open an action menu:
   - **View** — Open the issue in the browser
   - **Close** — Close the issue (with confirmation)
   - **Code** — Launch Claude Code autonomously in a separate git worktree
7. **Worktree Status** — Show per-card indicators for linked git worktrees (exists, dirty, active, ahead/behind)

### Stretch Features
- Move cards between columns (write back to GitHub)
- Create new issues from the board
- Filter by labels, assignees, milestones
- Multiple project support
- Polling for updates
- Live progress indicators for autonomous Claude sessions

## Technical Architecture

### Dependencies
- Neovim 0.9+ (for modern floating window APIs)
- `gh` CLI — required (authentication, GraphQL queries, issue management)
- `claude` CLI — optional (only needed for autonomous coding feature)
- Optional: nui.nvim or similar for UI components

### Authentication & Preflight
On first board open, the plugin runs a non-interactive preflight check:
1. Verify `gh` is installed and authenticated (hard requirement — board cannot function without it)
2. Verify `read:project` scope is available (required for Projects v2 GraphQL queries)
3. Check `claude` availability (soft requirement — board works without it, autonomous coding disabled)

If `read:project` scope is missing, the plugin guides the user to run `gh auth refresh --scopes read:project`. Claude auth is only verified lazily when the user first triggers the "Code" action. See [`docs/feature-architecture.md`](docs/feature-architecture.md) for the full preflight flow.

### API Layer
- GitHub Projects v2 uses **GraphQL only** (no REST API)
- Query via: `gh api graphql -f query='...'`
- Required scopes: `read:project`, `repo` (note: `read:project` is NOT granted by default in `gh auth login`)

### Key GraphQL Queries Needed
1. List user/org projects
2. Get project columns (status field)
3. Get project items (issues/PRs/drafts)
4. Get item details (title, body, labels, assignees)
5. Mutation: Update item field value (move between columns)

### UI Architecture
- **Board layout** — One floating window per column, positioned side-by-side
- **Sticky headers** — Column names via `winbar` or window `title` (never scroll away)
- **Card focus** — Extmark-based highlight on the selected card
- **Action menu** — Small floating window with single-key selection (a/b/c), no dependencies
- **Card detail view** — Split or float for full issue content
- **Project picker** — Telescope or native `vim.ui.select`

## File Structure (Planned)

```
okuban.nvim/
├── lua/
│   └── okuban/
│       ├── init.lua          # Plugin entry point, setup(), preflight checks
│       ├── api.lua           # GitHub GraphQL queries via gh CLI
│       ├── detect.lua        # Issue detection (branch, commits, gh CLI)
│       ├── worktree.lua      # Git worktree listing, status, mapping
│       ├── claude.lua        # Autonomous Claude Code session management
│       ├── ui/
│       │   ├── board.lua     # Kanban board layout (multi-window columns)
│       │   ├── card.lua      # Card rendering and detail view
│       │   ├── actions.lua   # Action menu popup (view/close/code)
│       │   └── picker.lua    # Project selector
│       ├── config.lua        # User configuration and defaults
│       └── utils.lua         # Helper functions
├── plugin/
│   └── okuban.lua            # Lazy-load setup
├── doc/
│   └── okuban.txt            # Neovim :help file (vimdoc format)
├── docs/
│   └── feature-architecture.md  # Detailed feature design and user flows
├── tests/
│   └── minimal_init.lua      # Headless test bootstrap
├── .claude/
│   ├── agents/               # Custom Claude Code agents
│   └── skills/               # Custom Claude Code skills
├── .github/
│   ├── workflows/            # CI: tests, linting, formatting
│   ├── ISSUE_TEMPLATE/       # Bug report and feature request templates
│   └── PULL_REQUEST_TEMPLATE.md
├── README.md                 # User-facing docs (install, config, usage)
├── CONTRIBUTING.md            # Contributor guide (dev setup, PR process)
├── CLAUDE.md
└── LICENSE
```

## Research & References

### Existing Plugins (Inspiration)
- **octo.nvim** — GitHub issues/PRs in Neovim (has Projects v2 card support, no kanban view)
- **kanban.nvim** — Local markdown kanban (UI inspiration)
- **super-kanban.nvim** — Keyboard-centric kanban (UX inspiration)
- **taskell** — Terminal kanban with GitHub import (one-off, likely deprecated API)

### GitHub Projects v2 API
- Docs: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects
- GraphQL Explorer: https://docs.github.com/en/graphql/overview/explorer
- Classic Projects sunset: June 2025

## Critical Instructions

- **Be self-critical** — always ask yourself:
  1. "Would I bet $100 on this working perfectly in production?"
  2. "Would a staff engineer approve this in code review?"
  - If either answer is "no" or "uncertain", investigate further before proceeding
- **User approval required** for all task completion, branch merging, and issue closure
- **Never close GitHub issues** without explicit user sign-off

### Surgical Code Changes
This codebase has interconnected logic. Unless the task explicitly requires broader changes:
- **Fix the specific problem** — don't refactor adjacent code "while you're there"
- **Preserve existing mechanisms** — if error handling or deduplication already exists, DON'T change it
- **Identify blast radius** — before changing shared code, list all callers/dependents
- **Ask yourself**: "Am I fixing one bug while creating another?" — if unsure, investigate first

### Balanced Elegance
Match solution complexity to problem complexity:
- **Simple bugs/fixes**: Apply simple, direct solutions — don't over-engineer
- **Complex changes**: Pause and ask "Is there a more elegant way?"
- **Hacky feeling?**: If a fix feels hacky, step back and implement the elegant solution
- **Challenge your work**: Before presenting, ask "Could this be simpler? Could this be cleaner?"

### Circuit Breaker — Stop and Re-Plan If:
- You encounter 2+ unexpected issues during implementation
- The fix requires touching more files than originally planned
- Tests fail in unexpected ways
- You're uncertain about the approach
- **When stopped**: Document what you learned, update the plan, get user confirmation before continuing

## Self-Improvement Loop

After ANY user correction, capture the lesson:
1. **Immediate**: Note the lesson in `MEMORY.md` with actionable rule
2. **Pattern detection**: If same lesson appears 3+ times, propose adding to relevant `docs/` file
3. **Review**: At session start, scan MEMORY.md for relevant lessons

**Memory Hierarchy**:
| Location | Purpose | Lifecycle |
|----------|---------|-----------|
| `context/` | Task-specific temporary files | Delete after task completion |
| `MEMORY.md` | Cross-session learnings | Keep concise (<200 lines), link to docs for details |
| `docs/*.md` | Graduated patterns | Permanent |
| GitHub Issues | Task tracking, bug documentation | Close when resolved |

## Subagent Strategy

**Use subagents liberally** — they keep main context clean and enable parallel work:
- **Context hygiene**: Offload research and exploration to subagents
- **Focused execution**: One task per subagent with clear responsibility
- **Parallel investigation**: For complex problems, launch multiple subagents for different aspects

**When to use which agent**:
| Agent | Use For |
|-------|---------|
| `Explore` | Searching/exploring codebase, finding patterns |
| `Plan` | Planning complex features, architectural decisions |

## Autonomous Bug Fixing

When given a bug report, **execute autonomously** — don't ask for hand-holding:

1. **Create/Update GitHub Issue** with steps to reproduce, expected vs actual behavior
2. **Document Root Cause** — investigation steps taken, root cause identified with evidence
3. **Plan Surgical Fix** — files to change (minimal blast radius), what MUST NOT change
4. **Implement & Test** — make changes, test affected components, verify fix with evidence
5. **Request User Approval** before closing issue

## Code Quality Rules

- **File size hard limit**: 500 lines maximum per file — refactor immediately if approaching
- **Feature branches**: `feature/issue-{#}-description`
- **Context management**: Use `/context/` for task-specific temporary files, cleanup after completion
- **Formatting**: StyLua (configured in `.stylua.toml`) — 2-space indent, 120 column width
- **Linting**: Luacheck (configured in `.luacheckrc`) — `vim` is a known global
- **Run before committing**: `/lua-lint` to check formatting and linting

## Testing

Tests use **plenary.nvim** with busted-style syntax.

### Running Tests
```bash
# All tests
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Single file
nvim --headless -c "PlenaryBustedFile tests/test_api_spec.lua"
```

Or use the skill: `/nvim-test`

### Test Conventions
- Test files live in `tests/` and end with `_spec.lua`
- Minimal init at `tests/minimal_init.lua` (loads only plenary + plugin)
- Use `describe` / `it` / `before_each` / `after_each` blocks

## Custom Agents

| Agent | Location | Purpose |
|-------|----------|---------|
| `lua-reviewer` | `.claude/agents/lua-reviewer.md` | Reviews Lua code for Neovim API best practices and plugin conventions |
| `api-explorer` | `.claude/agents/api-explorer.md` | Explores and tests GitHub Projects v2 GraphQL queries via `gh` CLI |

## Custom Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| `nvim-test` | `/nvim-test [file]` | Run plenary.nvim tests in headless mode |
| `gh-graphql` | `/gh-graphql [query]` | Test GitHub Projects v2 GraphQL queries |
| `lua-lint` | `/lua-lint [file]` | Run StyLua + Luacheck on Lua files |

## Documentation

### Open Source Documentation Standards

This plugin targets the Neovim open-source community. All documentation must be written to the standard of top-tier plugins (telescope.nvim, lazy.nvim, oil.nvim). Apply these rules:

**README.md** (the storefront):
- Lead with a GIF/screenshot showing the plugin in action
- One-sentence description, then install instructions within the first scroll
- Minimal viable config that works out of the box
- Full config reference with every option documented and its default value
- Keybinding table
- Prerequisites clearly listed (gh, Neovim version, optional deps)
- Troubleshooting section for common issues (missing scopes, auth failures)
- Badge row: Neovim version, license, CI status

**CONTRIBUTING.md** (the onramp for contributors):
- How to set up the dev environment (clone, install deps, run tests)
- Code style conventions (StyLua, Luacheck, 500-line limit)
- How to run tests locally
- PR process and what to expect
- Architecture overview with file-by-file descriptions
- Link to `docs/feature-architecture.md` for deeper design context
- "Good first issues" guidance

**doc/okuban.txt** (Neovim help file):
- Vimdoc format so users can run `:help okuban`
- Mirrors README content but in Neovim-native help syntax
- Generated or hand-written — must stay in sync with README

**GitHub repository setup**:
- Issue templates for bugs and feature requests
- PR template with checklist (tests pass, lint clean, docs updated)
- Labels for good-first-issue, help-wanted, bug, enhancement
- GitHub Actions CI: run tests, StyLua check, Luacheck

**When writing any documentation**:
- Assume the reader has never seen this plugin before
- Show, don't tell — use examples and code snippets over prose
- Keep install instructions copy-pasteable (no "adapt to your setup" hand-waving)
- Document every user-facing config option, command, and keybinding
- Update docs in the same PR as the code change — never let them drift

### Documentation Index

| Document | Purpose |
|----------|---------|
| [`docs/feature-architecture.md`](docs/feature-architecture.md) | Detailed feature design, user flows, and implementation approaches for all core features |
| `README.md` | User-facing: installation, usage, configuration, keybindings |
| `CONTRIBUTING.md` | Contributor-facing: dev setup, code style, PR process, architecture |
| `doc/okuban.txt` | Neovim `:help okuban` — vimdoc format |

## Development Notes

### Phase 1: Core Board
1. Authenticate via `gh` CLI
2. Fetch and parse project data via GraphQL
3. Render multi-column kanban with sticky headers
4. Semantic hjkl navigation
5. Auto-focus on current issue from git context

### Phase 2: Actions & Worktrees
1. Action menu on cards (view, close, code)
2. Worktree status indicators per card
3. Launch autonomous Claude Code sessions from the board
4. Refresh/sync

### Phase 3: Interactivity
1. Move cards between columns (GitHub mutation)
2. Create draft issues from the board
3. Monitor running Claude sessions with live status

### Phase 4: Polish & Community
1. Telescope integration for project picker
2. Customizable colors/highlights
3. Status line integration
4. GitHub Actions CI (tests, StyLua, Luacheck)
5. Issue templates, PR template, labels

### Documentation (continuous, every phase)
- README.md, CONTRIBUTING.md, and doc/okuban.txt are updated alongside code — never deferred
- Every new feature, config option, or keybinding must be documented before merge

## Commands (Planned)

```vim
:Okuban                  " Open kanban for current repo's project
:Okuban <project-name>   " Open specific project
:OkubanPick              " Pick project from list
:OkubanRefresh           " Refresh current board
:OkubanClose             " Close kanban overlay
```

## Keybindings (Planned)

| Key | Action |
|-----|--------|
| `h/l` | Move between columns |
| `j/k` | Move between cards |
| `<CR>` | Open action menu on selected card |
| `m` | Move card (enter move mode) |
| `n` | New draft issue |
| `r` | Refresh board |
| `q` | Close board |
| `?` | Show help |
| `g` | Jump to auto-detected current issue |

### Action Menu Keys
| Key | Action |
|-----|--------|
| `a` | View issue in browser |
| `b` | Close issue (with confirmation) |
| `c` | Code autonomously (worktree + Claude) |
| `<Esc>`/`q` | Dismiss menu |

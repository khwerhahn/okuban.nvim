# okuban.nvim

A Neovim plugin that turns GitHub issues into an interactive kanban board inside your editor.

## Issue-Driven Development

**ALL work must be tracked through GitHub Issues. No exceptions.**

Every feature, bug fix, refactor, docs update, and chore MUST have a corresponding GitHub issue before work begins. This applies to both human contributors and Claude Code sessions.

### Before Starting Any Work
1. Verify an issue exists: `gh issue view <NUMBER>`
2. If no issue exists, create one: `gh issue create --title "..." --body "..." --label "type: ..."`
3. Assign yourself: `gh issue edit <NUMBER> --add-assignee @me`
4. Apply the kanban label: `gh issue edit <NUMBER> --add-label "okuban:in-progress"`
5. Create a feature branch: `git checkout -b <type>/issue-<NUMBER>-<short-description>`
6. Use `/start-issue <NUMBER>` to automate steps 1-5

### Git Workflow

**NEVER commit or push directly to `main`.** All changes go through feature branches and pull requests.

```
main (protected) ← PR ← feature branch ← your commits
```

1. **Create a feature branch** from `main`: `git checkout -b <type>/issue-<NUMBER>-<description>`
2. **Commit to the feature branch** — never to `main`
3. **Push the feature branch** and open a PR: `gh pr create`
4. **CI must pass** (lint + tests on stable/nightly) before the PR can merge
5. **Merge via PR** — squash or merge commit, never direct push

If you find yourself on `main`, switch to a feature branch before making any changes. The `main` branch is protected by GitHub Rulesets — PRs and passing CI are required.

### Commit Message Format
```
<type>(<scope>): <description> (<keyword> #<issue>)
```
- **Types**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- **Keywords**: `Fixes #42`, `Closes #42`, `Resolves #42` (auto-close on merge), `Refs #42` (reference only)
- Example: `feat(ui): add kanban board column rendering (Fixes #42)`

### Branch Naming
```
<type>/issue-<NUMBER>-<short-description>
```
- Examples: `feat/issue-42-board-rendering`, `fix/issue-15-label-sync`, `docs/issue-7-readme`

### Pull Requests
- PR body MUST include `Fixes #<NUMBER>` or `Closes #<NUMBER>`
- GitHub auto-closes the issue when the PR merges

### After Completing Work
1. After PR is merged, **always run `/close-issue <NUMBER>`** — this is the single cleanup command that:
   - Moves the kanban label to `okuban:done`
   - Closes the issue with a completion comment
   - Closes any stale PRs linked to the issue
   - Deletes remote and local feature branches
   - Prunes stale git refs
2. **Never skip `/close-issue`** — GitHub auto-close (via `Fixes #N`) only closes the issue, it does NOT move the kanban label or clean up branches/PRs
3. For in-progress work not yet merged: `gh issue edit <NUMBER> --remove-label "okuban:in-progress" --add-label "okuban:review"`

### Why This Matters
- Issues are the single source of truth for all project work
- The kanban board (this plugin!) reads from issues — if work isn't tracked as an issue, it's invisible
- Contributors can see what's being worked on, what's done, and what needs help
- Git history links back to issue context (the "why" behind every change)

## Project Scope

### Core Goal
Turn any GitHub repo's issues into a kanban board inside Neovim using an opinionated label system. No GitHub Projects setup required — just issues and labels.

### Project Vision
This is an **open-source community plugin**. The primary goal is personal productivity (Neovim + tmux + Claude Code workflow), but the plugin must be built to attract and retain contributors from the Neovim community. This means:
- **Best-in-class documentation** — README, contributing guide, and inline help must be clear enough that anyone can install, use, and contribute within minutes
- **Low barrier to entry** — First-time contributors should be able to pick up an issue, understand the codebase, and submit a PR without needing to ask questions
- **Community standards** — Follow established Neovim plugin conventions so the project feels familiar to experienced plugin developers

### Target Features (MVP)
1. **Authentication** — Use `gh` CLI for GitHub auth (no custom token management)
2. **Label-Based Columns** — Opinionated default label system maps issues to kanban columns (fully configurable)
3. **Render Kanban** — Multi-column floating window layout with sticky headers and independent column scrolling
4. **Navigate** — Semantic hjkl navigation: h/l between columns, j/k between cards
5. **Move Cards** — Move issues between columns by swapping labels (`gh issue edit`)
6. **Auto-Focus** — Automatically detect the current issue from git context and scroll to it on board open
7. **Card Actions** — Press a key on any card to open an action menu:
   - **View** — Open the issue in the browser
   - **Close** — Close the issue (with confirmation)
   - **Code** — Launch Claude Code autonomously in a separate git worktree
8. **Worktree Status** — Show per-card indicators for linked git worktrees (exists, dirty, active, ahead/behind)

### Stretch Features
- Create new issues from the board
- Filter by assignees, milestones, custom labels
- Live progress indicators for autonomous Claude sessions
- Polling for updates

### v1.0 (post-beta)
- **GitHub Projects v2 integration** — Use Projects v2 as an alternative/additional data source alongside labels (GraphQL API, `read:project` scope). For growing teams where a project board adds value.

## Technical Architecture

### Dependencies
- Neovim 0.10+ (for `vim.ui.open`, improved `vim.system()`, modern floating window APIs)
- `gh` CLI — required (authentication, issue queries, label management)
- `claude` CLI — optional (only needed for autonomous coding feature)
- No external UI dependencies — native Neovim floating windows only

### Authentication & Preflight
On first board open, the plugin runs a non-interactive preflight check:
1. Verify `gh` is installed and authenticated (hard requirement — board cannot function without it)
2. Verify `repo` scope is available (default in `gh auth login`)
3. Check `claude` availability (soft requirement — board works without it, autonomous coding disabled)

Claude auth is only verified lazily when the user first triggers the "Code" action. See [`docs/feature-architecture.md`](docs/feature-architecture.md) for the full preflight flow.

### Data Model: Label-Based Kanban

Issues are sorted into kanban columns based on **labels**. The plugin ships with an opinionated default label set, fully configurable in `setup()`. Colors use GitHub's native palette for readability on both light and dark themes.

**Kanban column labels (prefix: `okuban:`)**:
| Label | Column | Color | Description |
|-------|--------|-------|-------------|
| `okuban:backlog` | Backlog | `#c5def5` (light blue) | Not yet planned |
| `okuban:todo` | Todo | `#0075ca` (blue) | Planned for work |
| `okuban:in-progress` | In Progress | `#fbca04` (yellow) | Actively being worked on |
| `okuban:review` | Review | `#d4c5f9` (lavender) | Awaiting review |
| `okuban:done` | Done | `#0e8a16` (green) | Completed |

Issues without any `okuban:` label appear in an **Unsorted** column (configurable: show/hide).

**Full label set** (created by `:OkubanSetup --full`):

Type labels:
| Label | Color | Description |
|-------|-------|-------------|
| `type: bug` | `#d73a4a` (red) | Something is not working |
| `type: feature` | `#0075ca` (blue) | New functionality |
| `type: docs` | `#fef2c0` (cream) | Documentation improvement |
| `type: chore` | `#e6e6e6` (gray) | Maintenance, refactoring, CI |

Priority labels:
| Label | Color | Description |
|-------|-------|-------------|
| `priority: critical` | `#d73a4a` (red) | Drop everything |
| `priority: high` | `#d93f0b` (orange) | Do this cycle |
| `priority: medium` | `#fbca04` (yellow) | Important but not urgent |
| `priority: low` | `#0e8a16` (green) | Backlog / nice-to-have |

Community labels:
| Label | Color | Description |
|-------|-------|-------------|
| `good first issue` | `#7057ff` (purple) | Good for newcomers |
| `help wanted` | `#008672` (teal) | Maintainer seeks help |
| `needs: triage` | `#fbca04` (yellow) | Needs initial assessment |
| `needs: repro` | `#fbca04` (yellow) | Needs reproduction steps |

**Setup commands**:
- `:OkubanSetup` — creates the 5 kanban column labels only
- `:OkubanSetup --full` — creates kanban labels + type + priority + community labels (~13 total)

**Moving a card between columns** = remove old label + add new label:
```
gh issue edit 42 --remove-label "okuban:todo" --add-label "okuban:in-progress"
```

Users can also set up labels manually — see `docs/label-setup.md` for the full `gh label create` commands.

### API Layer
- Uses `gh` CLI for all GitHub operations (no direct REST/GraphQL needed for v1)
- `gh issue list --label "okuban:todo" --json number,title,assignees,labels` per column
- `gh issue edit` for moving cards (label swap)
- `gh issue view` / `gh issue close` for card actions
- Required scope: `repo` (granted by default in `gh auth login`)

### Key Commands Used
1. `gh issue list --label <label> --json ...` — fetch issues per column
2. `gh issue edit <number> --remove-label <old> --add-label <new>` — move card
3. `gh issue view <number> --json ...` — card details
4. `gh issue close <number>` — close issue
5. `gh label create <name> --color <hex>` — setup labels

### UI Architecture
- **Board layout** — One floating window per column, positioned side-by-side
- **Sticky headers** — Column names via `winbar` or window `title` (never scroll away)
- **Card focus** — Extmark-based highlight on the selected card
- **Action menu** — Small floating window with single-key selection (a/b/c), no dependencies
- **Card detail view** — Split or float for full issue content
- **Repo picker** — Telescope or native `vim.ui.select`

## File Structure (Planned)

```
okuban.nvim/
├── lua/
│   └── okuban/
│       ├── init.lua          # Plugin entry point, setup(), preflight checks
│       ├── api.lua           # GitHub issue/label operations via gh CLI
│       ├── detect.lua        # Issue detection (branch, commits, gh CLI)
│       ├── worktree.lua      # Git worktree listing, status, mapping
│       ├── claude.lua        # Autonomous Claude Code session management
│       ├── ui/
│       │   ├── board.lua     # Kanban board layout (multi-window columns)
│       │   ├── card.lua      # Card rendering and detail view
│       │   ├── actions.lua   # Action menu popup (view/close/code)
│       │   └── picker.lua    # Repo selector
│       ├── config.lua        # User configuration and defaults
│       └── utils.lua         # Helper functions
├── plugin/
│   └── okuban.lua            # Lazy-load setup
├── doc/
│   └── okuban.txt            # Neovim :help file (vimdoc format)
├── docs/
│   └── feature-architecture.md  # Detailed feature design and user flows
├── tests/
│   ├── minimal_init.lua      # Headless test bootstrap
│   └── test_config_spec.lua  # Config defaults and label system tests
├── .claude/
│   ├── settings.json         # Hooks configuration (enforcement)
│   ├── agents/               # Custom Claude Code agents
│   │   ├── lua-reviewer.md   # Lua code review agent
│   │   └── api-explorer.md   # GitHub API exploration agent
│   ├── skills/               # Custom Claude Code skills
│   │   ├── start-issue/      # /start-issue — begin work on a GitHub issue
│   │   ├── close-issue/      # /close-issue — close a completed issue
│   │   ├── nvim-test/        # /nvim-test — run plenary.nvim tests
│   │   ├── gh-graphql/       # /gh-graphql — test gh CLI commands
│   │   └── lua-lint/         # /lua-lint — StyLua + Luacheck
│   └── hooks/                # Deterministic enforcement scripts
│       ├── validate-commit-issue-ref.sh  # Blocks commits without issue refs
│       └── load-issue-context.sh         # Auto-detects issue from branch
├── .github/
│   ├── workflows/
│   │   ├── ci.yml            # CI: StyLua + Luacheck + plenary tests (stable + nightly)
│   │   ├── pr-lint.yml       # PR title conventional commit lint
│   │   └── release.yml       # release-please + stable tag + LuaRocks publish
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

### GitHub API
- GitHub CLI manual: https://cli.github.com/manual/
- GitHub Issues API: https://docs.github.com/en/rest/issues
- GitHub Labels API: https://docs.github.com/en/rest/issues/labels
- GitHub Projects v2 API (future v2): https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects

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

- **Never commit to `main`**: Always use feature branches and PRs
- **File size hard limit**: 500 lines maximum per file — refactor immediately if approaching
- **Feature branches**: `<type>/issue-<#>-description` (e.g., `feat/issue-42-board-rendering`)
- **CI must pass**: Run `make check` (lint + test) before pushing. PRs are blocked until CI passes.
- **Context management**: Use `/context/` for task-specific temporary files, cleanup after completion
- **Formatting**: StyLua (configured in `.stylua.toml`) — 2-space indent, 120 column width
- **Linting**: Luacheck (configured in `.luacheckrc`) — `vim` is a known global
- **Run before committing**: `/lua-lint` to check formatting and linting

## Testing

Tests use **plenary.nvim** with busted-style syntax. **All code must pass tests before merging to main.**

### Running Tests
```bash
# All tests
make test

# Or directly:
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

# Single file
nvim --headless -c "PlenaryBustedFile tests/test_api_spec.lua"

# Full CI check (lint + test)
make check
```

Or use the skill: `/nvim-test`

### Test Conventions
- Test files live in `tests/` and end with `_spec.lua`
- Minimal init at `tests/minimal_init.lua` (loads only plenary + plugin)
- Use `describe` / `it` / `before_each` / `after_each` blocks
- **Test-driven development**: Write tests before or alongside code, never after

### CI Enforcement
GitHub Actions runs on every push to `main` and every PR:
- **Lint**: StyLua formatting check + Luacheck
- **Test**: plenary.nvim tests on Neovim stable + nightly
- **PR title lint**: Conventional commit format enforced on PR titles (`feat:`, `fix:`, etc.)

Branch protection (GitHub Rulesets) requires all CI checks to pass before merging. See `.github/workflows/`.

## Versioning & Releases

This project uses **SemVer** with `v`-prefixed tags and **release-please** for automated releases.

- **Beta** (`v0.x.y`): Label-based kanban (Phases 1-4)
- **v1.0.0**: Adds GitHub Projects v2 support (Phase 5)
- Conventional commit messages (`feat:`, `fix:`, `docs:`, etc.) drive automatic version bumps
- PR titles must follow conventional commit format (enforced in CI)
- `release-please` creates release PRs with changelogs on every push to main

### Release pipeline
When a release-please PR is merged:
1. A `v*` semver tag is created (e.g., `v0.1.0`)
2. A GitHub Release is published with auto-generated changelog
3. The `stable` tag is force-pushed to the release commit (for lazy.nvim `version = "*"`)
4. The plugin is published to LuaRocks (requires `LUAROCKS_API_KEY` secret)

## Custom Agents

| Agent | Location | Purpose |
|-------|----------|---------|
| `lua-reviewer` | `.claude/agents/lua-reviewer.md` | Reviews Lua code for Neovim API best practices and plugin conventions |
| `api-explorer` | `.claude/agents/api-explorer.md` | Explores and tests GitHub issue/label API operations via `gh` CLI |

## Custom Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| `start-issue` | `/start-issue <number>` | Start work on a GitHub issue (assign, branch, kanban label) |
| `close-issue` | `/close-issue <number>` | Close a GitHub issue (verify, label to done, close) |
| `nvim-test` | `/nvim-test [file]` | Run plenary.nvim tests in headless mode |
| `gh-graphql` | `/gh-graphql [query]` | Test GitHub API queries via `gh` CLI |
| `lua-lint` | `/lua-lint [file]` | Run StyLua + Luacheck on Lua files |

## Hooks (Enforcement)

| Hook | Event | Purpose |
|------|-------|---------|
| `validate-commit-issue-ref.sh` | `PreToolUse` (Bash) | Blocks commits that don't reference a GitHub issue |
| `load-issue-context.sh` | `SessionStart` | Auto-detects current issue from branch name and injects context |

Hooks are configured in `.claude/settings.json` and provide **deterministic enforcement** — they always run, unlike CLAUDE.md instructions which may be diluted in long conversations.

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
| [`docs/claude-code-workflow.md`](docs/claude-code-workflow.md) | How to use Claude Code with this project: skills, hooks, issue-driven workflow |
| `README.md` | User-facing: installation, usage, configuration, keybindings |
| `CONTRIBUTING.md` | Contributor-facing: dev setup, code style, PR process, architecture |
| `doc/okuban.txt` | Neovim `:help okuban` — vimdoc format |

## Development Notes

### Phase 1: Core Board
1. Authenticate via `gh` CLI
2. `:OkubanSetup` to create default labels on the repo
3. Fetch issues per label column via `gh issue list`
4. Render multi-column kanban with sticky headers
5. Semantic hjkl navigation
6. Move cards between columns (label swap)

### Phase 2: Smart Features
1. Auto-focus on current issue from git context
2. Worktree status indicators per card
3. Action menu on cards (view, close, code)
4. Refresh/sync

### Phase 3: Autonomous Coding
1. Launch Claude Code sessions from the board
2. Git worktree creation and management
3. Monitor running Claude sessions with live status

### Phase 4: Polish & Community
1. GitHub Actions CI (tests, StyLua, Luacheck)
2. Issue templates, PR template, labels

### Phase 5: GitHub Projects v2 (v1.0)
1. GitHub Projects v2 as alternative/additional data source (GraphQL API)
2. Custom field support (priority, iteration, size)
3. Sync between labels and project board columns

### Documentation (continuous, every phase)
- README.md, CONTRIBUTING.md, and doc/okuban.txt are updated alongside code — never deferred
- Every new feature, config option, or keybinding must be documented before merge

## Commands (Planned)

```vim
:Okuban                  " Open kanban for current repo
:OkubanSetup             " Create kanban column labels on the repo
:OkubanSetup --full      " Create kanban + type + priority + community labels
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

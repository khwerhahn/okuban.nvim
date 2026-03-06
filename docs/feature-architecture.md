# Feature Architecture & User Flows

This document details the design, user flows, and implementation approaches for okuban.nvim's core features. It serves as the authoritative reference for how each feature should work.

---

## Table of Contents

1. [Preflight & Authentication](#1-preflight--authentication)
2. [Board Layout & Rendering](#2-board-layout--rendering)
3. [Preview Pane](#3-preview-pane)
4. [Auto-Refresh & Staleness](#4-auto-refresh--staleness)
5. [Semantic Navigation (hjkl)](#5-semantic-navigation-hjkl)
6. [Auto-Focus on Current Issue](#6-auto-focus-on-current-issue)
7. [Action Menu](#7-action-menu)
8. [Onboarding & Triage](#8-onboarding--triage)
9. [Worktree Status Indicators](#9-worktree-status-indicators)
10. [Autonomous Claude Code Sessions](#10-autonomous-claude-code-sessions)
11. [GitHub Projects v2 Integration](#11-github-projects-v2-integration)

---

## 1. Preflight & Authentication

### Goal

Before the board can function, verify that required CLI tools are installed and authenticated. Fail fast with helpful error messages. Never trigger interactive login prompts.

### Two-Tier Dependency Model

The plugin has two tiers of dependencies:

**Hard requirement — `gh` CLI**:
- The board cannot function at all without `gh`. Every board operation (fetching projects, listing issues, closing issues, opening in browser) depends on it.
- Must be installed AND authenticated AND have the `repo` scope (default in `gh auth login`).

**Soft requirement — `claude` CLI**:
- Only needed for the "Code autonomously" action (action menu option `c`).
- The board works fully without it — the `c` action is simply disabled/hidden.
- Auth is verified lazily (only when user first triggers the Code action), not on board open.

### Preflight Check Flow (on `:Okuban`)

When the user runs `:Okuban`, the plugin runs these checks before rendering. All checks are non-interactive and never trigger browser prompts or login flows.

**Step 1 — Check `gh` is installed**:
- Method: `vim.fn.executable("gh") == 1`
- Speed: instant
- On failure: hard error — `"gh CLI not found. Install from https://cli.github.com"`

**Step 2 — Check `gh` is authenticated**:
- Method: `gh auth token` (exit code 0 = has stored token, non-zero = no auth)
- Speed: ~5ms, local only, never prompts
- On failure: hard error — `"Not authenticated. Run: gh auth login"`

**Step 3 — Check `repo` scope (verify access)**:
- Method: run a lightweight test command: `gh issue list --limit 1 --json number`
- Speed: ~400ms (network call, run async — show a loading indicator)
- On auth/scope error: hard error — `"Missing repo scope or no access to this repository. Run: gh auth refresh --scopes repo"`
- On success: proceed to render the board
- The `repo` scope is granted by default in `gh auth login`. This step mostly catches edge cases like expired tokens or fine-grained PATs with limited repo access.

**Step 4 — Check `claude` availability (non-blocking)**:
- Method: `vim.fn.executable("claude") == 1`
- Speed: instant
- On failure: soft warning — `"Claude Code not found. Autonomous coding disabled."` The board renders normally; the `c` action in the action menu is either hidden or shows a "Claude not available" message when selected.
- On success: store `claude_available = true` in plugin state. Do NOT verify auth yet.

### Lazy Claude Auth Check (on first "Code" action)

When the user selects a card and presses `c` (Code autonomously) for the first time in a session:

**Step 5 — Quick auth hint check (instant)**:
- Check `vim.env.ANTHROPIC_API_KEY` (API key auth)
- Check `vim.fn.filereadable("~/.claude/.credentials.json")` (OAuth credential file on Linux)
- On macOS, credentials are in the Keychain (harder to check — skip)
- If neither exists and not on macOS: warn the user — `"Claude Code may not be authenticated. Run: claude to log in."`
- If hints are present OR on macOS: proceed optimistically

**Step 6 — Actual auth test (only if Step 5 is ambiguous)**:
- Method: `claude -p "OK" --max-turns 1 --output-format text`
- Speed: ~2-5 seconds (makes an API call, costs minimal tokens)
- On failure (exit code non-zero): error — `"Claude Code authentication failed. Run: claude to log in."`
- On success: cache `claude_authenticated = true` for the rest of the session
- This check only runs ONCE per session. After success, all subsequent "Code" actions skip it.

### User Flow: First Time Setup

A new user installing the plugin for the first time:

```
1. User installs okuban.nvim, runs :Okuban
2. Plugin: "gh CLI not found. Install from https://cli.github.com"
   → User installs gh, runs :Okuban again

3. Plugin: "Not authenticated. Run: gh auth login"
   → User runs gh auth login, authenticates in browser, runs :Okuban again

4. Board opens successfully. "Claude Code not found. Autonomous coding disabled."
   → User can use the full board except the Code action.
   → If they install claude later, Code action becomes available next session.
```

### User Flow: Returning User (everything configured)

```
1. User runs :Okuban
2. Plugin checks gh (instant) ✓, checks auth (5ms) ✓
3. Board starts rendering, shows loading indicator
4. Issue list returns (400ms) ✓ — board populates with issues per label column
5. Claude check (instant) ✓ — Code action enabled
6. Board fully interactive
```

### Error Message Design

All error messages follow the pattern:
- **What's wrong** (clear, no jargon)
- **How to fix it** (the exact command to run)
- No stack traces or internal details unless `vim.g.okuban_debug` is set.

Examples:
- `"okuban: gh CLI not found. Install from https://cli.github.com"`
- `"okuban: Not authenticated with GitHub. Run: gh auth login"`
- `"okuban: Cannot access this repository. Check your gh auth scopes. Run: gh auth refresh --scopes repo"`
- `"okuban: Claude Code not installed. Autonomous coding disabled. Install from https://claude.ai/install.sh"`
- `"okuban: Claude Code authentication failed. Run: claude to log in."`

### Configuration

```lua
require("okuban").setup({
  -- Skip preflight checks (for users who know their setup works)
  skip_preflight = false,

  -- GitHub hostname (for Enterprise Server users)
  github_hostname = nil,  -- nil = auto-detect from git remote, or "github.example.com"
})
```

### GitHub Enterprise Server Considerations

If the user works with GHES:
- Detect hostname from the git remote URL in `.git/config`
- Pass `--hostname <host>` to `gh auth status` and `gh auth token`
- GHES may have different label defaults or API behavior — handle gracefully

### Token Types That Work

All of these token types work with `gh issue list/edit` and the plugin:

| Token Type | How to set up | Scope inspection |
|------------|--------------|-----------------|
| Browser OAuth (default) | `gh auth login` | Full (scopes visible) |
| Classic PAT | `gh auth login --with-token` | Full (scopes visible) |
| Fine-grained PAT | `gh auth login --with-token` | Limited (test query needed) |
| `GH_TOKEN` env var | `export GH_TOKEN=ghp_...` | Limited |
| `GITHUB_TOKEN` env var | `export GITHUB_TOKEN=ghp_...` | Limited |

### Claude Code Auth Methods

| Auth Method | Who uses it | Detection |
|-------------|------------|-----------|
| Claude.ai OAuth (Pro/Max) | Individual developers | Credential file or Keychain |
| `ANTHROPIC_API_KEY` env var | API pay-as-you-go users | Check env var |
| Console OAuth | Enterprise/Teams users | Credential file |
| AWS Bedrock | Cloud users | `CLAUDE_CODE_USE_BEDROCK` env var |
| `apiKeyHelper` script | Custom setups | Check settings.json |

Note: Free plan users do NOT have Claude Code CLI access. Pro ($20/month) is the minimum.

### Caching

- `gh` auth status: checked once on board open, cached for the session
- `repo` scope: verified once on board open via test issue list, cached for the session
- `claude` availability: checked once on board open (binary exists), cached for the session
- `claude` auth: checked once on first "Code" action, cached for the session
- All caches reset on new `:Okuban` session or `:OkubanRefresh`

---

## 2. Board Layout & Rendering

### Goal

Display label-based kanban columns side-by-side in a floating overlay, with sticky column headers and independent vertical scrolling per column.

### Approach: One Floating Window Per Column

Each kanban column (e.g., "Todo", "In Progress", "Done") becomes its own Neovim floating window. These windows are positioned side-by-side using calculated `col` offsets within a conceptual board area.

### Why Not a Single Buffer?

A single buffer with columns rendered as padded text was considered and rejected:
- Cannot scroll columns independently (fatal for boards where columns have very different card counts)
- Sticky headers are extremely difficult (headers scroll away with content)
- Navigation requires complex position math translating `(column, card)` to `(line, column_offset)`

### Sticky Column Headers

Column names stay visible at the top while cards scroll. Three viable approaches:

1. **`winbar`** (recommended) — Set a window-local winbar on each column window. Supports highlight groups and statusline-style format strings. Stays pinned at the top as content scrolls.
2. **Window `title`** — The `title` param on `nvim_open_win` renders text in the window border. Simpler but less flexible styling.
3. **Separate header windows** — A 1-line floating window above each column's content window. Maximum control but more windows to manage.

### Positioning Formula

Each column window is placed at:
- `row` = board top offset
- `col` = board left offset + (column_index - 1) * (column_width + gap)
- `width` = column_width (equal per column, or proportional to card count)
- `height` = board height

### nui.nvim Alternative

If nui.nvim is available, the layout can be expressed declaratively using `Layout.Box` with `dir = "row"` to arrange column `Popup` components horizontally. Each popup gets its own buffer, border, title, and keymaps. `layout:update()` handles dynamic resizing.

### Card Rendering Within a Column

Each card in a column buffer is rendered as a multi-line block:

```
┌─────────────────────────────┐
│ #42 Add OAuth login    [WT] │
│ @alice  labels: auth, ui    │
└─────────────────────────────┘
```

Cards are separated by blank lines. The selected card receives a highlight via extmarks.

### Two-Phase Rendering

1. **Phase 1 (immediate)**: Render columns and cards with basic info from `gh issue list` responses. Show worktree badges (`[WT]`) from `git worktree list --porcelain` (~4ms).
2. **Phase 2 (async)**: Fire parallel `vim.system()` calls for worktree dirty/clean status, ahead/behind counts. Update card indicators progressively as results arrive.

### Resize Handling

Listen for `VimResized` autocommand. Recalculate column positions and widths, then reposition all floating windows.

### Prior Art

- **super-kanban.nvim** — Each column and card is its own `Snacks.win` window. Board is a background window. Navigation moves focus between windows.
- **kanban.nvim** — Main floating window as container, column windows layered on top.
- **nui.nvim Layout** — Declarative horizontal/vertical box layout for floating popups.

---

## 3. Preview Pane

### Goal

Display contextual details about the currently selected card below the board columns, updating automatically as the user navigates between cards.

### Layout

The preview pane is a floating window positioned below the column windows with the same total width as the board. Height is controlled by `preview_lines` (default: 8 lines). The layout calculation allocates 75% of available height to columns and the remainder to the preview.

### Content

The preview pane shows structured issue details:

```
#42 Add OAuth login flow                    okuban:in-progress, type: feature
@alice @bob                                 ○ feat/issue-42-oauth
────────────────────────────────────────────────────────────────────────────────
Implement OAuth 2.0 login flow with Google and GitHub providers...
```

- **Line 1**: Issue number, title, labels
- **Line 2**: Assignees, worktree badge and branch name
- **Line 3**: Separator
- **Lines 4+**: Issue body excerpt (plain text, truncated to fit)

If a Claude session is running for the card, the preview also shows session info (status, turns, cost).

### Configuration

```lua
require("okuban").setup({
  preview_lines = 8,  -- 0 to disable preview pane
})
```

Setting `preview_lines = 0` hides the preview pane entirely, giving columns the full board height.

---

## 4. Auto-Refresh & Staleness

### Goal

Keep the board reasonably up-to-date without burning API quota or surprising the user with constant re-renders.

### Approach: Limited Auto-Refresh

On board open, the plugin starts a `vim.uv.new_timer()` that fires `auto_refresh_count` times (default: 3) at `poll_interval` intervals (default: 60 seconds). After the count is exhausted, auto-refresh stops.

This means the board gets ~3 automatic updates in the first few minutes, then stays static until the user manually refreshes with `r`.

### Staleness Indicator

The board header shows a subtle "time since last update" indicator that updates every 30 seconds:

```
okuban ──── r/repo-name ──── 2m ago
```

This gives the user a visual cue about data freshness without being intrusive. When the board was just refreshed, the indicator shows nothing.

### Manual Refresh

Pressing `r` triggers an immediate refresh AND restarts the auto-refresh cycle (counter resets to `auto_refresh_count`). This means the user can "wake up" auto-refresh at any time.

### Configuration

```lua
require("okuban").setup({
  poll_interval = 60,        -- seconds between auto-refreshes
  auto_refresh_count = 3,    -- number of auto-refreshes before stopping
})
```

### Why Not Continuous Polling?

Continuous polling (every N seconds forever) was implemented first and replaced. Problems:
- Wastes GitHub API rate limit on inactive boards
- Causes unexpected re-renders that disrupt navigation
- `gh issue list` is ~400ms — visible lag on each poll

The limited approach gives freshness when it matters (right after opening) and conserves resources after.

---

## 5. Semantic Navigation (hjkl + Arrow Keys)

### Goal

Navigate the kanban board with h/l between columns and j/k between cards. Arrow keys work identically. This is semantic navigation over a structured data model, not standard buffer cursor movement.

### State Model

The board maintains a logical cursor as a `(column_index, card_index)` pair, separate from any buffer cursor position:

```
state = {
  current_column = 2,
  current_card = 1,
  columns = { {name, cards}, {name, cards}, ... },
  scroll_offset = { [1]=0, [2]=0, [3]=0 },
}
```

### Navigation Behavior

**h (move left)** / **l (move right)**:
- Change `current_column` by -1/+1 (clamped to bounds)
- Call `nvim_set_current_win()` to move focus to the target column's window
- Preserve `current_card` index if possible; clamp to column length if the new column has fewer cards
- Restore scroll position for the target column

**j (move down)** / **k (move up)**:
- Change `current_card` by +1/-1 within the current column (clamped to bounds)
- Clear old highlight extmark, compute new card's line range, apply new highlight
- If the card is off-screen, scroll the column window to bring it into view
- Wrap-around is optional and configurable

### Visual Feedback

The focused card receives a highlight via `nvim_buf_set_extmark` with `hl_group = "OkubanCardFocused"` and `hl_eol = true`, covering the full card block (all lines of that card). Unfocused cards use the default buffer highlight.

### Keymap Setup

Buffer-local keymaps are set on each column buffer with `nowait = true` (ensures instant response, no waiting for multi-key sequences). Arrow keys (`<Left>`, `<Right>`, `<Up>`, `<Down>`) are mapped as aliases for h/l/k/j respectively, so both navigation styles work identically. Page up/down and gg/G are either remapped or disabled in the board buffers to prevent confusion.

### Prior Art

- **telescope.nvim** — Uses `action_state` to track selection. `move_selection_next/previous` updates an internal index and re-renders the highlight. Same conceptual pattern.
- **super-kanban.nvim** — Uses `context.location = { list = N, card = N }` to track focus. Navigation moves between `Snacks.win` instances.

---

## 6. Auto-Focus on Current Issue

### Goal

When the board opens, automatically detect which GitHub issue the user is currently working on and scroll/focus to that card. For large projects with many issues, this saves the user from manually finding their card.

### Detection Strategy: Cascading Tiers

Multiple signals are checked in priority order. Fast local signals render immediately; slower network signals confirm or correct asynchronously.

**Tier 1 — Git branch name (instant, ~2ms)**:
Parse the current branch name for issue number patterns. Common conventions:
- `feature/issue-42-description` → issue #42
- `fix/123-null-check` → issue #123
- `42-add-login` → issue #42
- `GH-42-oauth` → issue #42

The patterns should be user-configurable via `config.issue_detection.branch_patterns`.

**Tier 2 — Recent commit messages (fast, ~3ms)**:
Scan the last N commit subjects for `#42`, `Fixes #42`, `Closes #42` references. Count occurrences. Most-referenced issue is the best candidate. Useful as a confirmation signal for Tier 1.

**Tier 3 — GitHub CLI (authoritative, ~400ms)**:
Run `gh pr view --json closingIssuesReferences` to get:
- Which issues the current branch's PR closes

This is the most reliable signal but requires a network call. Run async; use Tier 1 result for immediate focus, then correct if Tier 3 disagrees.

**Tier 4 — Claude Code session (opportunistic, ~0ms)**:
Check `CLAUDE_SESSION_NAME` environment variable for issue references. Low reliability today but a future integration point as Claude Code exposes more metadata.

### User Flow

1. User runs `:Okuban` to open the board
2. Board renders immediately with all columns and cards
3. Tier 1 (branch name) result is available instantly — board scrolls to the matching card
4. Tier 3 (gh CLI) result arrives ~400ms later — if it differs from Tier 1, refocus silently
5. If no issue detected, board opens at the first column, first card — a subtle notification says "Could not detect current issue"
6. User can press `g` at any time to re-trigger auto-focus detection

### Caching

Detection results are cached with a configurable TTL (default: 60 seconds). Cache is invalidated on:
- `:OkubanRefresh` / `r` keybinding
- `BufEnter` when the git branch has changed
- Manual `g` keypress (force re-detect)

### Edge Cases

- **Detached HEAD**: No branch name available. Fall back to Tier 2/3.
- **No PR exists yet**: Tier 3 returns nothing. Rely on Tier 1/2.
- **Multiple issues in branch name**: Use the first match.
- **Branch name has no number**: Tier 1 returns nil, fall through to Tier 2.

---

## 7. Action Menu

### Goal

Press a key on any selected card to open a popup with contextual actions. Single keypress to select an action, no navigation needed.

### Approach: Custom Floating Window

A small floating window appears near the selected card with labeled options. Each option has a single-key shortcut. The menu auto-closes after selection or on dismiss.

### User Flow

1. User navigates to a card with hjkl
2. User presses `<CR>` to open the action menu
3. A small floating window appears near the card:

```
╭─ #42: Add OAuth login flow ──╮
│                                │
│  [m] Move to column...         │
│  [v] View in browser           │
│  [c] Close issue               │
│  [a] Assign to...              │
│  [w] Code with Claude          │
│                                │
│  [q] Cancel                    │
╰────────────────────────────────╯
```

4. User presses a single key to trigger the action
5. Menu closes immediately
6. Action executes (possibly with a confirmation step)
7. Pressing `<Esc>` or `q` dismisses the menu without acting

### Action Details

**m — Move to column** (core action, also available via `m` key outside menu):
- Opens a `vim.ui.select()` picker with available columns (excluding current)
- Runs `gh issue edit NUMBER --remove-label OLD --add-label NEW` async
- On success: triggers board refresh, card appears in new column
- This is the primary triage mechanism — users move issues from Unsorted into columns
- Also used for normal kanban workflow (todo → in-progress → review → done)

**v — View in browser**:
- Opens the issue URL in the system default browser
- Uses `vim.ui.open(url)` on Neovim 0.10+, falls back to `gh issue view NUMBER --web`
- Instant, no confirmation needed

**c — Close issue**:
- Shows a confirmation dialog via `vim.fn.confirm()` (default answer: No)
- On confirm: runs `gh issue close NUMBER` async
- On success: shows notification, triggers board refresh
- On cancel: menu closes, nothing happens

**a — Assign**:
- Assigns the issue to yourself: `gh issue edit NUMBER --add-assignee @me`
- Shows notification on success

**w — Code with Claude** (requires claude CLI):
- Creates a git worktree for the issue (if one doesn't already exist)
- Pre-fetches issue context via `gh issue view NUMBER --json title,body,labels,comments`
- Launches Claude Code in headless mode (`claude -p`) in the worktree directory
- Shows a notification that the session started
- Updates the card with a running indicator
- See [Section 10](#10-autonomous-claude-code-sessions) for full details

### Alternatives Considered

- **`vim.ui.select()`** — Simpler code but requires j/k + Enter (slower UX). Offered as a config option for users who prefer telescope/dressing.nvim routing.
- **nui.nvim Menu** — Richer API but adds a dependency for a small menu. Not justified.
- **which-key style** — Good for many actions, overkill for 3-5 options.

### Extensibility

The action list is a table. Future actions can be added:
- **Label** — Add/remove arbitrary labels
- **Comment** — Add a comment
- **Edit** — Edit title/body

---

## 8. Onboarding & Triage

### Goal

Make the board immediately useful on any existing repo — whether it has 0 issues or 200 — without bulk operations, notification spam, or a separate import workflow.

### Design Philosophy: The Board IS the Triage Tool

There is no `:OkubanImport` command. Instead:

- **Unsorted column = inbox.** Issues without `okuban:` labels naturally land here.
- **Action menu = triage.** Press `<CR>` on any card → "Move to column..." → done.
- **One notification per action.** Each move is a single `gh issue edit` call. No bulk spam.
- **User controls the pace.** Triage 5 issues today, 10 tomorrow. No urgency.

This is a deliberate design choice. Bulk-labeling 200 issues causes 200 email notifications to all repo watchers. The board-as-triage approach avoids this entirely.

### User Scenarios

**Scenario A: New repo, few issues**
1. `:OkubanSetup` → creates `okuban:` labels on the repo
2. `:Okuban` → board opens, existing issues appear in Unsorted
3. Navigate Unsorted → `<CR>` → "Move to column..." → pick column
4. New issues get tagged via `/start-issue` or `m` key on the board

**Scenario B: Existing repo with status labels** (e.g., `status: todo`, `in progress`)
1. No `:OkubanSetup` needed — configure existing labels as columns:

```lua
require('okuban').setup({
  columns = {
    { label = "status: backlog", name = "Backlog", color = "#c5def5" },
    { label = "status: todo",    name = "Todo",    color = "#0075ca" },
    { label = "in progress",     name = "In Progress", color = "#fbca04" },
    { label = "needs review",    name = "Review",  color = "#d4c5f9" },
    { label = "done",            name = "Done",    color = "#0e8a16", state = "all", limit = 20 },
  }
})
```

2. `:Okuban` → board reads existing labels, issues are already sorted
3. Zero modifications, zero notifications — config-only

**Scenario C: Existing repo, no status labels**
1. `:OkubanSetup` → creates `okuban:` labels
2. `:Okuban` → all issues land in Unsorted
3. User triages from Unsorted into columns via the action menu, at their own pace

### First-Open Hint

When the board opens and ALL kanban columns are empty but Unsorted has issues, display a one-line hint in the board header or preview pane:

```
Tip: press Enter on a card to triage it into a column, or m to move it directly
```

This hint disappears once at least one column has an issue.

### Automated Triage: `:OkubanTriage`

For repos with existing label systems, the `:OkubanTriage` command provides a semi-automated classification workflow:

1. Scans all open issues (optionally including closed)
2. Matches existing labels against a configurable pattern map (e.g., `"status: todo"` → `okuban:todo`, `"in progress"` → `okuban:in-progress`)
3. Builds a migration plan showing which issues would be moved to which columns
4. Applies the plan after user confirmation

This is distinct from the manual board triage (action menu) — it's a one-time tool for bootstrapping an existing repo's issues into the kanban system.

```lua
require("okuban").setup({
  triage = {
    enabled = true,
    include_closed = false,
  },
})
```

### What We Explicitly Do NOT Build

- **`:OkubanImport`** — No bulk import command. The board handles triage natively.
- **Label heuristic detection** — No scanning/guessing existing labels. Users configure in `setup()`.
- **Bulk-tagging** — No "tag all open issues as backlog" button. One-by-one is intentional.
- **Label migration** — No renaming or deleting existing labels. Additive only.

---

## 9. Worktree Status Indicators

### Goal

For each card on the board, show whether the issue has a linked git worktree and its status (dirty, clean, active, ahead/behind remote).

### Detection Mechanism

**Step 1 — List worktrees (~4ms)**:
Run `git worktree list --porcelain` and parse the output. Each entry provides:
- `worktree` — absolute path
- `HEAD` — commit SHA
- `branch` — full ref (e.g., `refs/heads/feature/issue-42`)
- `locked`, `detached`, `bare`, `prunable` flags

Parse using attribute-per-line approach (not fixed line counts — bare repos produce different output).

**Step 2 — Map worktree to issue**:
Extract issue number from the worktree's branch name using the same patterns as auto-focus detection. Cross-reference against the board's issue list to confirm the match.

**Step 3 — Get status (async, ~50-500ms per worktree)**:
For each worktree with a matched issue, fire parallel async calls:
- `git -C <path> status --porcelain` — dirty/clean
- `git -C <path> rev-list --left-right --count HEAD...@{upstream}` — ahead/behind

### Card Display

Cards with a linked worktree show indicators:

```
┌─────────────────────────────────┐
│ #42 Add OAuth login        [WT] │  ← [WT] = has worktree
│ @alice  ● feature/42-oauth      │  ← ● = dirty (uncommitted changes)
│ ↑2 ↓0  ⬤                       │  ← ↑2 ahead, ⬤ = active (current cwd)
└─────────────────────────────────┘
```

| Indicator | Meaning |
|-----------|---------|
| `[WT]` | Worktree exists for this issue |
| `●` | Worktree has uncommitted changes (dirty) |
| `○` | Worktree is clean |
| `⬤` | Worktree matches current Neovim working directory (active) |
| `↑N` | N commits ahead of remote |
| `↓N` | N commits behind remote |

### Highlight Groups

- `DiagnosticOk` (green) — clean worktrees
- `DiagnosticWarn` (yellow) — dirty worktrees
- `DiagnosticInfo` (blue) — active worktree (current cwd)
- `DiagnosticError` (red) — worktrees behind remote
- `Comment` (gray) — stale/inactive worktrees

### Active Worktree Detection

The "active" worktree is simply the one whose path matches `vim.fn.getcwd()`. No cross-instance Neovim detection (too fragile, minimal value).

### Performance

- `git worktree list --porcelain` is <10ms even with 20 worktrees (reads metadata only, no file inspection)
- Status checks are async and parallel; 10 worktrees complete within ~500ms wallclock
- Results cached with 30-second TTL, invalidated on refresh or `BufWritePost`/`FocusGained`
- For 20+ worktrees: batch status checks in groups of 5 to avoid excessive process spawning

### Optional Integration

If the user has **polarmutex/git-worktree.nvim** installed, register a hook on `Hooks.type.SWITCH` to auto-refresh worktree status when switching. This is an optional enhancement, not a dependency.

---

## 10. Autonomous Claude Code Sessions

### Goal

From the kanban board, select an issue and launch Claude Code to work on it autonomously in a separate git worktree. Monitor progress from within Neovim. Supports both headless (background) and tmux (interactive, visible) launch modes.

### Prerequisites

- `claude` CLI installed and authenticated (`claude --version` must succeed)
- `gh` CLI installed and authenticated
- Git repository with remote configured
- For tmux mode: running inside a tmux session (`$TMUX` must be set)

### User Flow

1. User navigates to a card, presses `<CR>`, then `x` (Code with Claude)
2. Plugin verifies `claude` CLI is available and authenticated (lazy check, first use only)
3. **Issue auto-moves to In Progress** — the current `okuban:` label is swapped to `okuban:in-progress` (no-op if already there; unsorted issues get the label added)
4. Plugin creates a git worktree: `feat/issue-{number}-claude` branch in `{repo}-worktrees/issue-{number}` (reuses existing worktree if already present)
5. Plugin fetches issue context: `gh issue view NUMBER --json number,title,body,labels,comments`
6. Plugin builds a structured prompt from issue context with context-gathering instructions (see [Prompt Architecture](#prompt-architecture))
7. Plugin launches Claude Code in the configured mode:

**Headless mode** (`launch_mode = "headless"`):
```
claude -p "{prompt}"
  --dangerously-skip-permissions
  --max-turns 30
  --max-budget-usd 5
  --output-format stream-json
  --append-system-prompt "RULES: 1) commit refs 2) feature branches 3) kanban labels 4) read CLAUDE.md"
  --allowedTools "Bash(git:*)" "Bash(gh:*)" "Read" "Edit" ...
```
Stream-json output is parsed via `vim.fn.jobstart()` `on_stdout` callback. Claude runs as a background process — no terminal UI is visible.

**Tmux mode** (`launch_mode = "tmux"` or `"auto"`):
Claude runs interactively in a **new tmux pane** split from an existing pane in the current window. The user can watch Claude work in real-time and follow up with additional instructions. The prompt is written to a temp file and read by a launcher script to avoid shell quoting issues with complex multi-line prompts.

```
tmux split-window -v -d -P -F '#{pane_id}' -t <target_pane>
  -c <worktree_path>
  <launcher_script>
```

The launcher script reads the prompt from file, runs `claude "$PROMPT" [flags]`, writes the exit code to a sentinel file, then cleans up after itself.

8. Card on the board shows a session badge: `[>]` running, `[+]` completed, `[!]` failed
9. On completion: notification with cost and turn count

### Launch Mode Selection

| `launch_mode` | Behavior |
|----------------|----------|
| `"auto"` (default) | Uses tmux if inside a tmux session (`$TMUX` set), otherwise falls back to headless |
| `"headless"` | Always runs as a background job via `vim.fn.jobstart()`. No visible terminal. |
| `"tmux"` | Always splits a tmux pane. Fails if not inside tmux. |

When `agent_teams.enabled = true`, launch mode is forced to `"tmux"` regardless of setting.

### Tmux Pane Splitting

In tmux mode, Claude runs in a **pane** (not a separate window), so the user can see Claude working alongside their Neovim session without switching windows.

**Split target selection** (`tmux_split.target`):
- `"auto"` (default) — Splits the widest non-Neovim pane in the current window. Falls back to splitting the Neovim pane if it's the only one.
- `"self"` — Always splits the Neovim pane.
- `"other"` — Prefers a non-Neovim pane, falls back to Neovim.

**Split direction** (`tmux_split.direction`):
- `"v"` (default) — Top/bottom stacking (vertical divider line). Best for typical `[Neovim | something]` layouts where you want Claude below.
- `"h"` — Side-by-side (horizontal divider line).

**Pane tagging**: Each Claude pane is tagged with a custom tmux option (`@okuban_issue`) to prevent duplicate panes for the same issue. The plugin checks for existing panes before splitting.

**Sentinel file**: A temp file that captures the exit code when Claude finishes. Polled every 2 seconds via `vim.uv.new_timer()`. The timer handle is stored on the session object to prevent garbage collection.

### Prompt Architecture

The autonomous Claude session receives two layers of instructions:

**Main prompt** (positional argument or `-p` flag):
1. Issue context: number, title, description, labels, recent comments
2. Structured instructions:
   - Read CLAUDE.md and explore the codebase to understand conventions and architecture
   - If the issue is vague or missing acceptance criteria, state assumptions before coding
   - Implement the changes and write tests if appropriate

**System prompt** (`--append-system-prompt`):
Explicit numbered rules that Claude must follow:
1. All commits must include `Fixes #N` or `Refs #N`
2. Work on a feature branch, never commit to main
3. If creating issues, always add an `okuban:` kanban label
4. Read CLAUDE.md before starting — it has project conventions

The worktree is a full clone with access to CLAUDE.md, `.claude/` hooks, skills, and settings. This means Claude has the same project conventions available as a human developer.

### Action Menu States

The `x` key in the action menu adapts based on session state:
- **No session**: "Code with Claude" — launches a new session
- **Running**: "Claude is running..." — informational only
- **Completed/Failed with session_id**: "Resume Claude session" — resumes via `claude --resume <session_id>`

### Session Management

```lua
active_sessions = {
  [42] = {
    job_id = 123,           -- vim.fn.jobstart() ID (headless) or nil (tmux)
    session_id = "uuid",    -- from stream-json init event (headless only)
    worktree_path = "/path/to/worktree-42",
    status = "running",     -- initializing | running | completed | failed
    turns = 5,
    cost_usd = 0.42,
    num_turns = 8,
    started_at = timestamp,
    sentinel_path = "/tmp/xxx.okuban-sentinel",  -- tmux mode only
    pane_id = "%42",        -- tmux pane ID (tmux mode only)
    poll_timer = <uv_timer>, -- sentinel poll timer (tmux mode only)
  },
}
```

### Monitoring

**Stream-json events** (headless mode) provide real-time updates:
- `type: "system", subtype: "init"` — session started, captures `session_id`
- `type: "assistant"` — Claude is working, increment turn count
- `type: "result"` — session finished, includes `total_cost_usd`, `num_turns`, `is_error`

**Sentinel file** (tmux mode): a temporary file written with the exit code when the command completes. Polled every 2 seconds via `vim.uv.new_timer()`. The timer handle is stored in `session.poll_timer` to prevent garbage collection. When the sentinel is found, the timer stops and the exit code determines session status.

### Security & Cost Control

- **`--dangerously-skip-permissions`** — required for non-interactive mode. Tool access is still scoped via `--allowedTools`
- **Budget cap** via `--max-budget-usd` (default $5)
- **Turn limit** via `--max-turns` (default 30)
- **Worktree isolation** — Claude operates in a separate worktree, not the main working tree
- **System prompt rules** — explicit numbered rules for commit refs, branch policy, kanban labels, and project conventions
- **Prompt file** — in tmux mode, the prompt is written to a temp file and read by the launcher script, avoiding shell injection risks from complex prompts

### Post-Completion Actions

Automated actions triggered after a successful headless session (configurable):
- **auto_push** — pushes the worktree branch: `git -C <worktree> push -u origin HEAD`
- **auto_pr** — creates a PR: `gh pr create --head <branch> --title "feat: address #N" --body "Fixes #N"`

Both default to `false`. Errors are reported via notifications but don't block.

### Session Resume

Completed or failed sessions can be resumed from the action menu:
```
claude --resume <session_id> --output-format stream-json
```
Resume reuses the existing worktree and session state. The `session_id` is captured from the stream-json `init` event during headless mode. In tmux mode, session resume is not currently supported (no `session_id` is captured from the interactive TUI).

### Agent Teams (Experimental)

> **Status:** Experimental. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
> This feature depends on Anthropic's agent teams API which is in active development.
> Configuration and behavior may change. Last verified: February 2026.

When `agent_teams.enabled = true`:
- Environment variable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set
- `--teammate-mode <mode>` flag is added to the command (default: "tmux")
- Launch mode is forced to "tmux" (agent teams require an interactive terminal)

### Configuration

```lua
require("okuban").setup({
  claude = {
    enabled = true,             -- enable Claude Code integration
    max_budget_usd = 5.00,      -- max spend per session
    max_turns = 30,             -- max agentic turns per session
    model = nil,                -- override model (e.g. "sonnet", "opus")
    launch_mode = "auto",       -- "auto" (tmux if available), "headless", or "tmux"
    allowed_tools = {           -- Claude Code tool allowlist
      "Bash(git:*)", "Bash(gh:*)",
      "Read", "Edit", "Write", "Glob", "Grep",
    },
    worktree_base_dir = nil,    -- nil = {repo}-worktrees/, or custom path
    auto_push = false,          -- push branch after successful completion
    auto_pr = false,            -- create PR after successful completion
    tmux_split = {              -- tmux pane splitting options
      target = "auto",          -- "auto" | "self" | "other"
      direction = "v",          -- "v" (top/bottom) | "h" (side-by-side)
      size = nil,               -- pane size (e.g. "50%"), nil = tmux default
    },
    agent_teams = {             -- EXPERIMENTAL: Claude agent teams
      enabled = false,
      teammate_mode = "tmux",   -- "tmux" or "auto"
    },
  },
})
```

### Module Structure

- **`lua/okuban/claude.lua`** (~500 lines) — Session lifecycle: availability check, auth, worktree creation, issue context, prompt/command building, stream-json parsing, headless launch, tmux launch, resume, stop
- **`lua/okuban/tmux.lua`** (~300 lines) — Tmux pane management: availability check, pane listing/tagging, split target selection, launcher script generation (headless and interactive), prompt file writing, sentinel polling
- **`lua/okuban/ui/actions.lua`** — Action menu with 3-state Claude logic, auto-move to in-progress on launch

### Prior Art

- **ccpm** — Project management using GitHub Issues and git worktrees for parallel Claude agent execution
- **@agenttools/worktree** — CLI tool that creates worktrees from issues, generates context files, launches Claude in tmux sessions
- **claude-flow** — Multi-agent orchestration with swarm intelligence

---

## 11. GitHub Projects v2 Integration

### Goal

Provide an alternative data source for the kanban board using GitHub Projects v2 instead of (or alongside) labels. For teams that outgrow the label-based approach.

### Switching Data Sources: `:OkubanSource`

The `:OkubanSource` command allows switching between label-based and Projects-based boards at runtime:

```vim
:OkubanSource labels           " Switch to label-based kanban (default)
:OkubanSource project           " Switch to auto-detected project
:OkubanSource project 42        " Switch to specific project number
```

The choice is persisted per-repo. If the board is open when switching, it closes and reopens with the new data source.

### API Layer

Projects v2 uses the GitHub GraphQL API via `gh api graphql`:
- List project items with status field values
- Move items between status columns
- Requires `read:project` scope (not included by default — user must run `gh auth refresh --scopes read:project`)

The implementation lives in `lua/okuban/api_project.lua`, separate from the label-based API in `lua/okuban/api.lua`.

### Label Migration: `:OkubanMigrate`

For repos transitioning from labels to Projects v2, `:OkubanMigrate` provides a migration path:
- Maps existing `okuban:` labels to project status field values
- Creates project items for issues that aren't already in the project
- Preserves the label-based board as a fallback

### Configuration

```lua
require("okuban").setup({
  source = "labels",              -- "labels" or "project"
  project = {
    number = nil,                 -- auto-detect or specific project number
    status_field = "Status",      -- name of the Status field in the project
  },
})
```

---

## Appendix: Key Technical References

### Neovim APIs Used

| API | Purpose |
|-----|---------|
| `nvim_open_win` | Create floating windows for columns and menus |
| `nvim_set_current_win` | Move focus between column windows |
| `nvim_buf_set_extmark` | Highlight focused card, card decorations |
| `nvim_create_autocmd` | Resize handling, cleanup, buffer events |
| `vim.system()` | Async shell commands (git, gh) |
| `vim.fn.jobstart()` | Launch Claude Code as background process |
| `vim.keymap.set` | Buffer-local keymaps with `nowait` |
| `vim.ui.open` | Open URLs in browser (0.10+) |
| `vim.fn.confirm` | Confirmation dialogs |
| `vim.json.decode` | Parse gh CLI JSON output and stream-json events |
| `vim.notify` | User-facing notifications |

### CLI Tools

| Tool | Purpose |
|------|---------|
| `gh issue list --label <label> --json ...` | Fetch issues per column (label-based) |
| `gh issue edit --remove-label --add-label` | Move cards between columns (label swap) |
| `gh label create` | Create kanban labels on a repo |
| `gh pr view` | Get current branch's PR and linked issues |
| `gh issue view` | Fetch issue details, open in browser |
| `gh issue close` | Close an issue |
| `git worktree list --porcelain` | List all worktrees with metadata |
| `git -C <path> status --porcelain` | Check worktree dirty/clean status |
| `git rev-parse --abbrev-ref HEAD` | Get current branch name |
| `git log --format=%s -n N` | Scan recent commit messages |
| `claude -p` | Run Claude Code headless |

### Existing Plugins Studied

| Plugin | What We Learned |
|--------|----------------|
| super-kanban.nvim | Multi-window layout, per-card windows, context.location state |
| kanban.nvim | Container window with column overlays |
| octo.nvim | GitHub issue commands, `gh` CLI integration patterns |
| telescope.nvim | Selection state management, action dispatch |
| which-key.nvim | Contextual popup menu triggered by key sequence |
| polarmutex/git-worktree.nvim | Worktree hook system, buffer path mapping |

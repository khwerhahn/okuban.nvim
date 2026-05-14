local card = require("okuban.ui.card")
local claude = require("okuban.claude")
local config = require("okuban.config")
local header = require("okuban.ui.header")
local utils = require("okuban.utils")
local worktree = require("okuban.worktree")

local Board = {}
Board.__index = Board

-- Singleton instance
local instance = nil

--- Highlight groups with sensible defaults.
local function define_highlights()
  vim.api.nvim_set_hl(0, "OkubanCardFocused", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "OkubanColumnHeader", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "OkubanCardActive", { default = true, link = "WarningMsg" })
  vim.api.nvim_set_hl(0, "OkubanBackdrop", { default = true, bg = "#000000", fg = "#000000", blend = 40 })
  vim.api.nvim_set_hl(0, "OkubanLogo", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "OkubanLogoTrunk", { default = true, link = "Comment" })
end

local ns_active = vim.api.nvim_create_namespace("okuban_worktree_active")

--- Calculate layout dimensions for the board.
--- Includes space for a 1-line header bar above the columns.
---@param num_cols integer
---@param screen_width integer|nil
---@param screen_height integer|nil
---@param preview_lines integer|nil Height of preview pane (0 or nil to disable)
---@param show_logo boolean|nil Show ASCII logo above header (adds 6 rows)
---@return table
function Board.calculate_layout(num_cols, screen_width, screen_height, preview_lines, show_logo)
  local sw = screen_width or vim.o.columns
  local sh = screen_height or vim.o.lines
  preview_lines = preview_lines or 0

  local board_width = math.floor(sw * 0.9)
  local gap = 1
  local col_width = math.floor((board_width - (num_cols - 1) * gap) / num_cols)

  -- Enforce minimum column width
  local min_col_width = 20
  if col_width < min_col_width then
    col_width = min_col_width
    board_width = num_cols * col_width + (num_cols - 1) * gap
  end

  local total_height = math.floor(sh * 0.8)

  -- Header: 1 line content + 2 border + 1 gap below = 4 rows
  local header_inner = 1
  local header_border = 2
  local header_gap = 1
  local header_space = header_inner + header_border + header_gap

  -- Logo: 6 lines above header (canopy + trunk/pot)
  local logo_height = show_logo and 6 or 0

  if preview_lines > 0 then
    -- Columns get 75% of available height, preview gets the rest
    local available = total_height - header_space - logo_height - 3 -- 3 = 2 (preview border) + 1 (gap)
    local board_height = math.floor(available * 0.75)
    board_height = math.floor(board_height * 0.8) -- 20% column height reduction for scroll
    if board_height < 5 then
      board_height = 5
    end
    local effective_preview = available - board_height

    -- Center the total visual block: logo + header + gap + columns + gap + preview
    local total_visual = logo_height
      + (header_inner + header_border)
      + header_gap
      + board_height
      + 2
      + 1
      + effective_preview
      + 2
    local block_start = math.floor((sh - total_visual) / 2)
    local header_row = block_start + logo_height
    local start_row = header_row + header_space
    local start_col = math.floor((sw - board_width) / 2)
    local preview_row = start_row + board_height + 2 + 1

    local result = {
      board_width = board_width,
      board_height = board_height,
      col_width = col_width,
      start_row = start_row,
      start_col = start_col,
      gap = gap,
      header_row = header_row,
      header_height = header_inner,
      preview_height = effective_preview,
      preview_row = preview_row,
    }
    if show_logo then
      result.logo_row = block_start
    end
    return result
  else
    local board_height = math.floor((total_height - header_space - logo_height) * 0.8)
    if board_height < 5 then
      board_height = 5
    end

    -- Center the total visual block: logo + header + gap + columns
    local total_visual = logo_height + (header_inner + header_border) + header_gap + board_height + 2
    local block_start = math.floor((sh - total_visual) / 2)
    local header_row = block_start + logo_height
    local start_row = header_row + header_space
    local start_col = math.floor((sw - board_width) / 2)

    local result = {
      board_width = board_width,
      board_height = board_height,
      col_width = col_width,
      start_row = start_row,
      start_col = start_col,
      gap = gap,
      header_row = header_row,
      header_height = header_inner,
    }
    if show_logo then
      result.logo_row = block_start
    end
    return result
  end
end

--- Compute per-column widths, optionally expanding one column.
--- When focus_col is nil, all columns get equal width.
--- When focus_col is set, that column gets extra width and others shrink.
---@param num_cols integer
---@param board_width integer Total board width
---@param gap integer Gap between columns
---@param focus_col integer|nil Column to expand (1-indexed)
---@param multiplier number|nil Expansion multiplier (default 1.8)
---@return integer[] widths Per-column widths
function Board.compute_column_widths(num_cols, board_width, gap, focus_col, multiplier)
  local total_gaps = (num_cols - 1) * gap
  local available = board_width - total_gaps
  local base_width = math.floor(available / num_cols)
  local min_width = 20

  if not focus_col or num_cols <= 1 then
    local widths = {}
    for _ = 1, num_cols do
      table.insert(widths, base_width)
    end
    return widths
  end

  multiplier = multiplier or 1.8
  local expanded = math.floor(base_width * multiplier)

  -- Compute shrunk width for other columns
  local shrunk = math.floor((available - expanded) / (num_cols - 1))

  -- Enforce minimum width on shrunk columns
  if shrunk < min_width then
    shrunk = min_width
    expanded = available - shrunk * (num_cols - 1)
    -- If expanded is now smaller than base, don't bother expanding
    if expanded <= base_width then
      local widths = {}
      for _ = 1, num_cols do
        table.insert(widths, base_width)
      end
      return widths
    end
  end

  local widths = {}
  for i = 1, num_cols do
    if i == focus_col then
      table.insert(widths, expanded)
    else
      table.insert(widths, shrunk)
    end
  end
  return widths
end

--- Create a new Board instance.
---@return table
function Board.new()
  local o = setmetatable({}, Board)
  o.windows = {}
  o.buffers = {}
  o.data = nil
  o.augroup = nil
  o.preview_win = nil
  o.preview_buf = nil
  o._poll_timer = nil
  o._polling = false
  o._auto_refresh_remaining = 0
  o.sub_issue_counts = {}
  o._expanded_col_idx = nil
  return o
end

--- Build the column list for display from board data.
--- Always emits the Unsorted column when `data.unsorted` is set (i.e.
--- `show_unsorted = true`), even if empty. Matches `open_loading`'s window
--- count so `populate` does not fall back to the synchronous `Board:open`
--- path, which would skip the async parent_map fetch and leave sub-issues
--- unfiltered.
---@param data table Board data from api.fetch_all_columns
---@return table[] cols
local function build_column_list(data)
  local cols = {}
  for _, col in ipairs(data.columns) do
    table.insert(cols, { name = col.name, issues = col.issues, limit = col.limit, has_more = col.has_more })
  end
  if data.unsorted then
    table.insert(cols, { name = "Unsorted", issues = data.unsorted })
  end
  return cols
end

--- Format column title with issue count.
---@param name string Column display name
---@param issue_count integer Number of issues in the column
---@param limit integer|nil Max fetch limit for the column
---@return string
local function format_title(name, issue_count, limit)
  if limit and issue_count >= limit then
    return string.format(" %s (%d+) ", name, limit)
  end
  return string.format(" %s (%d) ", name, issue_count)
end

--- Drop leaf sub-issues from each column in place. An issue is a leaf
--- sub-issue when it has a GitHub parent AND has no children of its own.
--- Roots (no parent) and mid-level parents (have parent but also have
--- children) stay visible as top-level cards. Leaves are reachable via
--- tree expansion on their parent.
---
--- `sub_issue_counts` indicates which issues have children. When omitted
--- (e.g. the cached-warm Board:open fallback path), the filter is a no-op
--- so a mid-level parent isn't accidentally hidden as a leaf — populate's
--- async barrier will repaint with the real counts shortly.
---@param cols table[] Column list from build_column_list
---@param parent_map table<integer, integer>|nil
---@param sub_issue_counts table<integer, {total: integer, completed: integer}>|nil
---@return boolean filtered_any True if at least one issue was removed
local function filter_sub_issues_in_place(cols, parent_map, sub_issue_counts)
  if not parent_map or vim.tbl_isempty(parent_map) then
    return false
  end
  if not sub_issue_counts then
    return false
  end
  local filtered_any = false
  for _, col in ipairs(cols) do
    local original_count = #col.issues
    local filtered = {}
    for _, issue in ipairs(col.issues) do
      local has_parent = parent_map[issue.number] ~= nil
      local has_children = sub_issue_counts[issue.number] ~= nil
      if not has_parent or has_children then
        table.insert(filtered, issue)
      end
    end
    if #filtered < original_count then
      col.issues = filtered
      filtered_any = true
    end
  end
  return filtered_any
end

--- Create the preview window below the column windows.
---@param layout table Layout from calculate_layout
function Board:_create_preview_window(layout)
  if not layout.preview_height or layout.preview_height <= 0 then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "okuban"

  local empty_lines = {}
  for _ = 1, layout.preview_height do
    table.insert(empty_lines, "")
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, empty_lines)
  vim.bo[buf].modifiable = false

  local source = config.get().source or "labels"
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = layout.preview_row,
    col = layout.start_col,
    width = layout.board_width,
    height = layout.preview_height,
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
    footer = " " .. source .. " ",
    footer_pos = "right",
    focusable = false,
    zindex = 50,
  })

  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  self.preview_win = win
  self.preview_buf = buf

  -- Set up close keymap on preview buffer
  local keymaps = config.get().keymaps
  vim.keymap.set("n", keymaps.close, function()
    self:close()
  end, { buffer = buf, nowait = true, silent = true })
end

--- Apply orange highlight to cards that have an active worktree.
--- Uses a separate namespace so it persists alongside focus highlights.
---@param wt_map table<integer, table>|nil Worktree map
function Board:_apply_active_highlights(wt_map)
  -- Clear previous active highlights on all buffers
  for _, buf in ipairs(self.buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_active, 0, -1)
    end
  end

  if not wt_map or not self.columns then
    return
  end

  for i, col in ipairs(self.columns) do
    local buf = self.buffers[i]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      for card_idx, issue in ipairs(col.issues) do
        if wt_map[issue.number] and wt_map[issue.number].active then
          local ranges = col.card_ranges
          if ranges and ranges[card_idx] then
            for line_nr = ranges[card_idx].start_line, ranges[card_idx].end_line do
              vim.api.nvim_buf_add_highlight(buf, ns_active, "OkubanCardActive", line_nr - 1, 0, -1)
            end
          end
        end
      end
    end
  end
end

--- Update the preview pane with the given issue's details.
---@param issue table|nil
function Board:update_preview(issue)
  if not self.preview_buf or not vim.api.nvim_buf_is_valid(self.preview_buf) then
    return
  end
  local cfg = config.get()
  local preview_lines = cfg.preview_lines or 0
  if preview_lines <= 0 then
    return
  end

  local num_cols = #self.windows
  local layout = Board.calculate_layout(num_cols, nil, nil, preview_lines, cfg.show_logo)
  local inner_width = layout.board_width - 2
  local sessions = claude.get_all_sessions()
  local lines =
    card.render_preview(issue, inner_width, layout.preview_height, self.worktree_map, sessions, self.sub_issue_counts)

  vim.bo[self.preview_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, lines)
  vim.bo[self.preview_buf].modifiable = false
end

--- Start a limited auto-refresh cycle.
--- Fetches data `auto_refresh_count` times at `poll_interval` intervals,
--- then stops. Call this after the initial data fetch or after a manual refresh.
function Board:_start_auto_refresh()
  self:_stop_auto_refresh()
  local cfg = config.get()
  local interval = (cfg.poll_interval or 60) * 1000
  local count = cfg.auto_refresh_count or 3

  if interval <= 0 or count <= 0 then
    return
  end

  self._auto_refresh_remaining = count
  self._polling = false

  local timer = vim.uv.new_timer()
  timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      if not self:is_open() or self._polling then
        return
      end
      if self._auto_refresh_remaining <= 0 then
        self:_stop_auto_refresh()
        return
      end

      self._polling = true
      self._auto_refresh_remaining = self._auto_refresh_remaining - 1

      local api = require("okuban.api")
      api.fetch_all_columns(function(data)
        self._polling = false
        if data and self:is_open() then
          self:refresh(data)
        end
        if self._auto_refresh_remaining <= 0 then
          self:_stop_auto_refresh()
        end
      end)
    end)
  )
  self._poll_timer = timer
end

--- Stop auto-refresh timer and reset remaining count.
function Board:_stop_auto_refresh()
  if self._poll_timer then
    self._poll_timer:stop()
    self._poll_timer:close()
    self._poll_timer = nil
  end
  self._polling = false
  self._auto_refresh_remaining = 0
end

--- Set up common autocommands (VimResized, WinClosed, WinEnter).
function Board:_setup_autocommands()
  vim.api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      self:_reposition()
    end,
  })

  -- The board is modal: it only closes on explicit user action (q / Esc).
  -- If focus escapes (wincmd, mouse click, tmux pane switch, etc.), refocus
  -- back to the board instead of closing.  This follows the same pattern as
  -- lazy.nvim's :Lazy popup and other modal floating UIs.

  vim.api.nvim_create_autocmd({ "WinEnter", "FocusGained" }, {
    group = self.augroup,
    callback = function()
      vim.schedule(function()
        self:_refocus_if_escaped()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      -- Logo windows are decorative — don't close the board when they close
      if header.is_logo_win(closed_win) then
        return
      end
      local hwin = header.get_win()
      if hwin and hwin == closed_win then
        vim.schedule(function()
          self:close()
        end)
        return
      end
      if self.preview_win and self.preview_win == closed_win then
        vim.schedule(function()
          self:close()
        end)
        return
      end
      for _, w in ipairs(self.windows) do
        if w == closed_win then
          vim.schedule(function()
            self:close()
          end)
          return
        end
      end
    end,
  })
end

--- Open the board with loading placeholders (instant skeleton).
--- No navigation is set up — call populate(data) when data arrives.
function Board:open_loading()
  -- Idempotent: if windows already exist (e.g., a concurrent open() raced
  -- ahead), bail rather than appending another set.
  if self:is_open() then
    return
  end

  define_highlights()

  local cfg = config.get()
  local columns = cfg.columns
  local num_cols = #columns + (cfg.show_unsorted and 1 or 0)

  if num_cols == 0 then
    utils.notify("No columns configured", vim.log.levels.WARN)
    return
  end

  local preview_lines = cfg.preview_lines or 0
  local layout = Board.calculate_layout(num_cols, nil, nil, preview_lines, cfg.show_logo)
  self.augroup = vim.api.nvim_create_augroup("OkubanBoard", { clear = true })

  -- Create header bar above columns
  header.create(layout)

  -- Build placeholder column names
  local col_names = {}
  for _, col in ipairs(columns) do
    table.insert(col_names, col.name)
  end
  if cfg.show_unsorted then
    table.insert(col_names, "Unsorted")
  end

  for i = 1, num_cols do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "okuban"

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  Loading..." })
    vim.bo[buf].modifiable = false

    local col_offset = (i - 1) * (layout.col_width + layout.gap)
    local win_col = layout.start_col + col_offset

    local title = string.format(" %s ", col_names[i] or "")
    local win = vim.api.nvim_open_win(buf, i == 1, {
      relative = "editor",
      row = layout.start_row,
      col = win_col,
      width = layout.col_width,
      height = layout.board_height,
      style = "minimal",
      border = "rounded",
      title = title,
      title_pos = "center",
      focusable = true,
      zindex = 50,
    })

    vim.wo[win].cursorline = false
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"

    table.insert(self.windows, win)
    table.insert(self.buffers, buf)
  end

  -- Create preview window
  self:_create_preview_window(layout)

  -- Set up close keymaps on loading buffers
  local keymaps = cfg.keymaps
  local tmux = require("okuban.tmux")
  for _, buf in ipairs(self.buffers) do
    local buf_opts = { buffer = buf, nowait = true, silent = true }
    vim.keymap.set("n", keymaps.close, function()
      self:close()
    end, buf_opts)
    if keymaps.close ~= "<Esc>" then
      vim.keymap.set("n", "<Esc>", function()
        self:close()
      end, buf_opts)
    end
    -- Block wincmd / ctrl-nav from escaping floats (same as navigation keymaps)
    local tmux_dirs = { ["h"] = "L", ["j"] = "D", ["k"] = "U", ["l"] = "R" }
    for key, dir in pairs(tmux_dirs) do
      local switch_pane = function()
        if tmux.is_available() then
          vim.system({ "tmux", "select-pane", "-" .. dir })
        end
      end
      vim.keymap.set("n", "<C-" .. key .. ">", switch_pane, buf_opts)
      vim.keymap.set("n", "<C-w>" .. key, switch_pane, buf_opts)
      vim.keymap.set("n", "<C-w><C-" .. key .. ">", switch_pane, buf_opts)
    end
  end

  self:_setup_autocommands()
  self:_start_loading_animation()
end

--- Animated loading text frames (ASCII-only).
local LOADING_FRAMES = { "Loading.  ", "Loading.. ", "Loading...", "Loading.. " }

--- Start a buffer-text animation that cycles "Loading..." across all column
--- buffers until the first paint replaces them. No-op if already running.
function Board:_start_loading_animation()
  if self._loading_timer then
    return
  end
  local frame_idx = 1

  local function render_frame()
    if not self:is_open() or self.columns then
      self:_stop_loading_animation()
      return
    end
    local text = "  " .. LOADING_FRAMES[frame_idx]
    for _, buf in ipairs(self.buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
        vim.bo[buf].modifiable = false
      end
    end
    frame_idx = (frame_idx % #LOADING_FRAMES) + 1
  end

  self._loading_timer = vim.uv.new_timer()
  self._loading_timer:start(0, 250, vim.schedule_wrap(render_frame))
end

--- Stop the loading animation and free the timer. Idempotent.
function Board:_stop_loading_animation()
  if self._loading_timer then
    self._loading_timer:stop()
    self._loading_timer:close()
    self._loading_timer = nil
  end
end

--- Render the given column list to existing buffers, update window titles,
--- store columns on self, and apply active-worktree highlights.
---@param cols table[]
---@param layout table
---@param wt_map table<integer, table>|nil
---@param sessions table
---@param counts table|nil sub-issue counts
function Board:_paint_columns(cols, layout, wt_map, sessions, counts)
  for i, col in ipairs(cols) do
    local buf = self.buffers[i]
    local win = self.windows[i]

    if buf and vim.api.nvim_buf_is_valid(buf) then
      local inner_width = layout.col_width - 2
      local lines, card_ranges = card.render_column(col.issues, inner_width, wt_map, sessions, counts or {})
      col.card_ranges = card_ranges

      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    end

    if win and vim.api.nvim_win_is_valid(win) then
      local title = format_title(col.name, #col.issues, col.limit)
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = layout.start_row,
        col = layout.start_col + (i - 1) * (layout.col_width + layout.gap),
        width = layout.col_width,
        height = layout.board_height,
        title = title,
        title_pos = "center",
      })
    end
  end

  self.columns = cols
  self:_apply_active_highlights(wt_map)
end

--- Set up navigation for the first time or refresh it while preserving position.
function Board:_setup_or_update_navigation()
  local Navigation = require("okuban.ui.navigation")
  if self.navigation then
    local old_col = self.navigation.column_index
    local old_card = self.navigation.card_index
    local old_issue_mode = self.navigation.issue_mode
    self.navigation = Navigation.new(self)
    self.navigation.column_index = math.min(old_col, self.navigation:num_columns())
    local count = self.navigation:card_count(self.navigation.column_index)
    self.navigation.card_index = math.min(old_card, math.max(1, count))
    self.navigation.issue_mode = old_issue_mode or false
  else
    self.navigation = Navigation.new(self)
  end
  for _, buf in ipairs(self.buffers) do
    self.navigation:setup_keymaps(buf)
  end
  self.navigation:highlight_current()
end

--- Inject parents referenced by fetched children that are not themselves
--- in the fetched data. Mutates `data.columns[i].issues` in place by
--- appending each newly-fetched parent into the column whose okuban:
--- label it carries. Extends `parent_map` and `counts` with any new
--- parent/child or count info discovered during the fetch, then recurses
--- so transitive ancestors are pulled in too.
---
--- Bounded depth: stops after MAX_DEPTH passes to defend against
--- pathological GitHub data (cycles, runaway hierarchies).
---@param data table Board data from api.fetch_all_columns
---@param parent_map table<integer, integer> Mutated; new entries added
---@param counts table<integer, {total: integer, completed: integer}> Mutated
---@param callback fun()
local function inject_missing_parents(data, parent_map, counts, callback)
  local MAX_DEPTH = 5
  local depth = 0
  local label_to_col = {}
  for col_idx, col in ipairs(data.columns) do
    if col.label then
      label_to_col[col.label] = col_idx
    end
  end

  local function step()
    local visible = {}
    for _, col in ipairs(data.columns) do
      for _, issue in ipairs(col.issues) do
        visible[issue.number] = true
      end
    end
    if data.unsorted then
      for _, issue in ipairs(data.unsorted) do
        visible[issue.number] = true
      end
    end

    local missing = {}
    for _, parent_num in pairs(parent_map) do
      if not visible[parent_num] and not missing[parent_num] then
        missing[parent_num] = true
      end
    end
    local missing_list = {}
    for num in pairs(missing) do
      table.insert(missing_list, num)
    end
    if #missing_list == 0 or depth >= MAX_DEPTH then
      -- Re-sort each column so injected parents land in the right position
      -- per the configured sort (default: updatedAt desc).
      local api_labels = require("okuban.api_labels")
      if api_labels.sort_issues then
        for _, col in ipairs(data.columns) do
          api_labels.sort_issues(col.issues)
        end
      end
      callback()
      return
    end
    depth = depth + 1

    local api = require("okuban.api")
    api.fetch_issue_details(missing_list, function(parents, new_parents, new_counts)
      for _, parent in ipairs(parents) do
        local placed = false
        for _, label in ipairs(parent.labels or {}) do
          local target = label_to_col[label.name]
          if target and data.columns[target] then
            table.insert(data.columns[target].issues, parent)
            placed = true
            break
          end
        end
        -- Parent with no matching okuban: label is intentionally not
        -- injected: it would have no home column. Its children remain
        -- hidden by the leaf filter and unreachable from the board,
        -- which is the user's responsibility to fix (label the parent).
        local _ = placed
      end
      for k, v in pairs(new_parents) do
        parent_map[k] = v
      end
      for k, v in pairs(new_counts) do
        counts[k] = v
      end
      step()
    end)
  end

  step()
end

--- Populate existing loading windows with real data in-place.
--- Waits for ALL async data fetches (worktree enrichment + sub-issue
--- metadata) before painting so the user sees one fully-formed render
--- instead of a sequence of partial renders. The buffers retain their
--- prior contents (loading skeleton on cold open, previous cards on
--- refresh) until the single paint fires.
---@param data table Board data from api.fetch_all_columns
---@param on_painted fun()|nil Called once after the single paint completes.
function Board:populate(data, on_painted)
  self.data = data
  local cols = build_column_list(data)

  -- If column count doesn't match windows, fall back to close+open
  if #cols ~= #self.windows then
    self:close()
    self:open(data)
    if on_painted then
      on_painted()
    end
    return
  end

  if #cols == 0 then
    self:close()
    utils.notify("No columns to display", vim.log.levels.WARN)
    return
  end

  require("okuban.ui.tree").reset()
  self._expanded_col_idx = nil

  local cfg = config.get()
  local preview_lines = cfg.preview_lines or 0
  local layout = Board.calculate_layout(#cols, nil, nil, preview_lines, cfg.show_logo)
  self._layout = layout

  -- Verify headless session liveness before rendering badges
  claude.verify_sessions()

  -- Sync worktree fetch (~4ms). Used as a fallback if enrichment times out.
  local wt_map = worktree.fetch_worktree_map()

  -- Generation guard: subsequent populate calls invalidate prior async chains.
  self._populate_gen = (self._populate_gen or 0) + 1
  local gen = self._populate_gen

  -- Cached parent_map serves as fallback when fetch_sub_issue_counts hangs
  -- so the timeout render still strips known sub-issues.
  local api = require("okuban.api")
  local cached_parent_map = (api.get_cached_parent_map and api.get_cached_parent_map()) or nil

  -- Collect raw issue numbers for the sub-issue count GraphQL query.
  local all_numbers = {}
  for _, raw_col in ipairs(build_column_list(data)) do
    for _, issue in ipairs(raw_col.issues) do
      table.insert(all_numbers, issue.number)
    end
  end

  -- Async barrier: paint_now fires once both fetches resolve (or after the
  -- safety-net timeout). All paint state is captured here so callbacks
  -- compose into a single render.
  local pending = 2 -- worktree.fetch_enriched + fetch_sub_issue_counts
  local painted = false
  local enriched_wt_map = nil
  local fresh_counts = nil
  local fresh_parent_map = nil

  local function paint_now()
    if painted or self._populate_gen ~= gen or not self:is_open() then
      return
    end
    painted = true
    self:_stop_loading_animation()

    local pm = fresh_parent_map or cached_parent_map or {}
    self.sub_issue_counts = fresh_counts or self.sub_issue_counts or {}
    local final_cols = build_column_list(data)
    filter_sub_issues_in_place(final_cols, pm, self.sub_issue_counts)
    self.worktree_map = enriched_wt_map or wt_map

    self:_paint_columns(final_cols, layout, self.worktree_map, claude.get_all_sessions(), self.sub_issue_counts)
    self:_setup_or_update_navigation()

    header.set_last_updated(os.time())

    if on_painted then
      on_painted()
    end
  end

  local function on_async_done()
    if self._populate_gen ~= gen then
      return
    end
    pending = pending - 1
    if pending <= 0 then
      paint_now()
    end
  end

  worktree.fetch_enriched(function(em)
    enriched_wt_map = em
    on_async_done()
  end)

  if #all_numbers == 0 then
    fresh_counts = {}
    fresh_parent_map = {}
    on_async_done()
  else
    api.fetch_sub_issue_counts(all_numbers, function(counts, pm)
      fresh_counts = counts
      fresh_parent_map = pm
      -- Pull in parents referenced by fetched children that fell outside
      -- `initial_fetch_limit`. Each newly-injected parent is appended to
      -- `data.columns[i].issues` based on its okuban: label, so the leaf
      -- filter has a complete picture of which parents are on the board.
      inject_missing_parents(data, fresh_parent_map, fresh_counts, function()
        if self._populate_gen ~= gen then
          return
        end
        on_async_done()
      end)
    end)
  end

  -- Safety net: if any fetch hangs (network failure, gh crash), paint with
  -- whatever we have rather than leaving the user stuck. paint_now is
  -- guarded by `painted` and the generation counter so a redundant call is
  -- a no-op.
  vim.defer_fn(paint_now, 2500)
end

--- Open the board with the given data (immediate, no loading phase).
---@param data table Board data from api.fetch_all_columns
function Board:open(data)
  self.data = data
  define_highlights()

  local cols = build_column_list(data)

  if #cols == 0 then
    utils.notify("No columns to display", vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local preview_lines = cfg.preview_lines or 0
  local layout = Board.calculate_layout(#cols, nil, nil, preview_lines, cfg.show_logo)
  self._layout = layout
  self.augroup = vim.api.nvim_create_augroup("OkubanBoard", { clear = true })

  -- Create header bar above columns
  header.create(layout)

  -- Verify headless session liveness before rendering badges
  claude.verify_sessions()

  -- Fetch worktree map for card badges
  local wt_map = worktree.fetch_worktree_map()
  self.worktree_map = wt_map
  local sessions = claude.get_all_sessions()

  -- Apply cached parent_map filter pre-render (warm path; matches populate).
  -- Without cached sub_issue_counts the filter is a no-op (it can't tell
  -- mid-level parents from leaves), so populate's full async barrier path
  -- will repaint with the correct filter shortly.
  local api_module = require("okuban.api")
  local cached_parent_map = (api_module.get_cached_parent_map and api_module.get_cached_parent_map()) or nil
  if cached_parent_map and not vim.tbl_isempty(cached_parent_map) then
    filter_sub_issues_in_place(cols, cached_parent_map, self.sub_issue_counts)
  end

  for i, col in ipairs(cols) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "okuban"

    local inner_width = layout.col_width - 2
    local lines, card_ranges = card.render_column(col.issues, inner_width, wt_map, sessions, self.sub_issue_counts)
    col.card_ranges = card_ranges
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local col_offset = (i - 1) * (layout.col_width + layout.gap)
    local win_col = layout.start_col + col_offset

    local title = format_title(col.name, #col.issues, col.limit)
    local win = vim.api.nvim_open_win(buf, i == 1, {
      relative = "editor",
      row = layout.start_row,
      col = win_col,
      width = layout.col_width,
      height = layout.board_height,
      style = "minimal",
      border = "rounded",
      title = title,
      title_pos = "center",
      focusable = true,
      zindex = 50,
    })

    vim.wo[win].cursorline = false
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"

    table.insert(self.windows, win)
    table.insert(self.buffers, buf)
  end

  self.columns = cols

  -- Create preview window
  self:_create_preview_window(layout)

  -- Apply orange highlight to active worktree cards
  self:_apply_active_highlights(wt_map)

  -- Set up navigation (highlight_current will also update preview)
  local Navigation = require("okuban.ui.navigation")
  self.navigation = Navigation.new(self)
  for _, buf in ipairs(self.buffers) do
    self.navigation:setup_keymaps(buf)
  end
  self.navigation:highlight_current()

  self:_setup_autocommands()

  -- Record update timestamp (auto-refresh cycle is managed by callers)
  header.set_last_updated(os.time())
end

--- If the current window is not a board window (focus escaped via wincmd,
--- mouse click, tmux pane switch, etc.), refocus back to the board.
--- The board is modal and only closes via explicit q / Esc.
function Board:_refocus_if_escaped()
  if not self:is_open() then
    return
  end
  local win = vim.api.nvim_get_current_win()
  for _, w in ipairs(self.windows) do
    if w == win then
      return
    end
  end
  if self.preview_win and self.preview_win == win then
    return
  end
  -- Allow okuban popup windows (actions menu, help, vim.ui.select).
  -- win is from nvim_get_current_win() so it is always valid.
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == "okuban" then
    return
  end
  -- Refocus back to the board
  if self.navigation then
    self.navigation:_focus_window()
  else
    for _, w in ipairs(self.windows) do
      if vim.api.nvim_win_is_valid(w) then
        vim.api.nvim_set_current_win(w)
        break
      end
    end
  end
end

--- Reposition all windows after a resize.
--- Preserves column expansion state if a column is currently expanded.
function Board:_reposition()
  if #self.windows == 0 then
    return
  end

  local cfg = config.get()
  local preview_lines = cfg.preview_lines or 0
  local num_cols = #self.windows
  local layout = Board.calculate_layout(num_cols, nil, nil, preview_lines, cfg.show_logo)
  self._layout = layout

  local widths = Board.compute_column_widths(num_cols, layout.board_width, layout.gap, self._expanded_col_idx)

  local col_offset = 0
  for i, win in ipairs(self.windows) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = layout.start_row,
        col = layout.start_col + col_offset,
        width = widths[i],
        height = layout.board_height,
      })
    end
    col_offset = col_offset + widths[i] + layout.gap
  end

  -- Reposition header window
  header.reposition(layout)

  -- Reposition preview window
  if self.preview_win and vim.api.nvim_win_is_valid(self.preview_win) and layout.preview_row then
    vim.api.nvim_win_set_config(self.preview_win, {
      relative = "editor",
      row = layout.preview_row,
      col = layout.start_col,
      width = layout.board_width,
      height = layout.preview_height,
    })
  end

  -- Re-render expanded column with new width if applicable
  if self._expanded_col_idx and self.navigation then
    self.navigation:_rerender_column(self._expanded_col_idx)
    self.navigation:highlight_current()
  end

  -- Update scroll indicators after resize (window height may have changed)
  if self.navigation then
    self.navigation:update_scroll_indicators()
  end
end

--- Expand a column visually by making it wider and shrinking others.
--- Updates all window positions and sizes via nvim_win_set_config.
---@param col_idx integer Column to expand (1-indexed)
function Board:_apply_column_expansion(col_idx)
  if #self.windows == 0 or not self._layout then
    return
  end

  self._expanded_col_idx = col_idx
  local layout = self._layout
  local num_cols = #self.windows
  local widths = Board.compute_column_widths(num_cols, layout.board_width, layout.gap, col_idx)

  local col_offset = 0
  for i, win in ipairs(self.windows) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = layout.start_row,
        col = layout.start_col + col_offset,
        width = widths[i],
        height = layout.board_height,
      })
    end
    col_offset = col_offset + widths[i] + layout.gap
  end
end

--- Restore all columns to equal width (undo expansion).
function Board:_restore_column_widths()
  if #self.windows == 0 or not self._layout then
    return
  end

  self._expanded_col_idx = nil
  local layout = self._layout
  local num_cols = #self.windows
  local widths = Board.compute_column_widths(num_cols, layout.board_width, layout.gap, nil)

  local col_offset = 0
  for i, win in ipairs(self.windows) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = layout.start_row,
        col = layout.start_col + col_offset,
        width = widths[i],
        height = layout.board_height,
      })
    end
    col_offset = col_offset + widths[i] + layout.gap
  end
end

--- Get the current width of a specific column (expanded or normal).
---@param col_idx integer
---@return integer
function Board:get_column_width(col_idx)
  if not self._layout then
    return 20
  end
  local num_cols = #self.windows
  local widths =
    Board.compute_column_widths(num_cols, self._layout.board_width, self._layout.gap, self._expanded_col_idx)
  return widths[col_idx] or self._layout.col_width
end

--- Close the board and clean up all windows and buffers.
function Board:close()
  self:_stop_auto_refresh()
  self:_stop_loading_animation()
  require("okuban.ui.tree").reset()

  if self.augroup then
    vim.api.nvim_del_augroup_by_id(self.augroup)
    self.augroup = nil
  end

  -- Close any open popup windows (action menu, help) and header
  require("okuban.ui.actions").close()
  require("okuban.ui.create").close()
  require("okuban.ui.help").close()
  header.close()

  -- Close preview window
  if self.preview_win and vim.api.nvim_win_is_valid(self.preview_win) then
    vim.api.nvim_win_close(self.preview_win, true)
  end
  self.preview_win = nil
  self.preview_buf = nil
  self._expanded_col_idx = nil

  for _, win in ipairs(self.windows) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Buffers with bufhidden=wipe are cleaned up automatically
  self.windows = {}
  self.buffers = {}
  self.columns = nil
  self.data = nil
  self.navigation = nil
  instance = nil
end

--- Refresh the board with new data.
--- If column count matches, updates in-place. Otherwise closes and reopens.
---@param data table Board data from api.fetch_all_columns
function Board:refresh(data)
  local cols = build_column_list(data)
  if #cols == #self.windows and #self.windows > 0 then
    self:populate(data)
  else
    self:close()
    self:open(data)
  end
end

--- Check if the board is currently open.
---@return boolean
function Board:is_open()
  return #self.windows > 0
end

-- ---------------------------------------------------------------------------
-- Singleton access
-- ---------------------------------------------------------------------------

--- Get or create the singleton board instance.
---@return table
function Board.get_instance()
  if not instance then
    instance = Board.new()
  end
  return instance
end

--- Close the singleton instance if it exists.
function Board.close_instance()
  if instance then
    instance:close()
  end
end

Board._build_column_list = build_column_list
Board._filter_sub_issues_in_place = filter_sub_issues_in_place
Board._inject_missing_parents = inject_missing_parents

return Board

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
end

local ns_active = vim.api.nvim_create_namespace("okuban_worktree_active")

--- Calculate layout dimensions for the board.
--- Includes space for a 1-line header bar above the columns.
---@param num_cols integer
---@param screen_width integer|nil
---@param screen_height integer|nil
---@param preview_lines integer|nil Height of preview pane (0 or nil to disable)
---@return table
function Board.calculate_layout(num_cols, screen_width, screen_height, preview_lines)
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

  if preview_lines > 0 then
    -- Columns get 75% of available height, preview gets the rest
    local available = total_height - header_space - 3 -- 3 = 2 (preview border) + 1 (gap)
    local board_height = math.floor(available * 0.75)
    board_height = math.floor(board_height * 0.8) -- 20% column height reduction for scroll
    if board_height < 5 then
      board_height = 5
    end
    local effective_preview = available - board_height

    -- Center the total visual block: header + gap + columns + gap + preview
    local total_visual = (header_inner + header_border) + header_gap + board_height + 2 + 1 + effective_preview + 2
    local block_start = math.floor((sh - total_visual) / 2)
    local header_row = block_start
    local start_row = block_start + header_space
    local start_col = math.floor((sw - board_width) / 2)
    local preview_row = start_row + board_height + 2 + 1

    return {
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
  else
    local board_height = math.floor((total_height - header_space) * 0.8)
    if board_height < 5 then
      board_height = 5
    end

    -- Center the total visual block: header + gap + columns
    local total_visual = (header_inner + header_border) + header_gap + board_height + 2
    local block_start = math.floor((sh - total_visual) / 2)
    local header_row = block_start
    local start_row = block_start + header_space
    local start_col = math.floor((sw - board_width) / 2)

    return {
      board_width = board_width,
      board_height = board_height,
      col_width = col_width,
      start_row = start_row,
      start_col = start_col,
      gap = gap,
      header_row = header_row,
      header_height = header_inner,
    }
  end
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
  o.sub_issue_counts = {}
  return o
end

--- Build the column list for display from board data.
---@param data table Board data from api.fetch_all_columns
---@return table[] cols
local function build_column_list(data)
  local cols = {}
  for _, col in ipairs(data.columns) do
    table.insert(cols, { name = col.name, issues = col.issues, limit = col.limit, has_more = col.has_more })
  end
  if data.unsorted and #data.unsorted > 0 then
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
  local layout = Board.calculate_layout(num_cols, nil, nil, preview_lines)
  local inner_width = layout.board_width - 2
  local sessions = claude.get_all_sessions()
  local lines =
    card.render_preview(issue, inner_width, layout.preview_height, self.worktree_map, sessions, self.sub_issue_counts)

  vim.bo[self.preview_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, lines)
  vim.bo[self.preview_buf].modifiable = false
end

--- Start auto-refresh polling timer.
function Board:_start_polling()
  self:_stop_polling()
  local cfg = config.get()
  local interval = (cfg.poll_interval or 20) * 1000
  if interval <= 0 then
    return
  end

  self._polling = false
  local timer = vim.uv.new_timer()
  timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      if not self:is_open() or self._polling then
        return
      end
      self._polling = true
      local api = require("okuban.api")
      api.fetch_all_columns(function(data)
        self._polling = false
        if data and self:is_open() then
          self:refresh(data)
        end
      end)
    end)
  )
  self._poll_timer = timer
end

--- Stop auto-refresh polling timer.
function Board:_stop_polling()
  if self._poll_timer then
    self._poll_timer:stop()
    self._poll_timer:close()
    self._poll_timer = nil
  end
  self._polling = false
end

--- Set up common autocommands (VimResized, WinClosed, WinEnter).
function Board:_setup_autocommands()
  vim.api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      self:_reposition()
    end,
  })

  -- Close board if focus escapes to a non-board window (e.g. clicking outside)
  vim.api.nvim_create_autocmd("WinEnter", {
    group = self.augroup,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      for _, w in ipairs(self.windows) do
        if w == win then
          return
        end
      end
      if self.preview_win and self.preview_win == win then
        return
      end
      -- Allow okuban popup windows (actions menu, help, vim.ui.select)
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      if ft == "okuban" then
        return
      end
      -- Entered a non-board window — close the board
      vim.schedule(function()
        self:close()
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
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
  define_highlights()

  local cfg = config.get()
  local columns = cfg.columns
  local num_cols = #columns + (cfg.show_unsorted and 1 or 0)

  if num_cols == 0 then
    utils.notify("No columns configured", vim.log.levels.WARN)
    return
  end

  local preview_lines = cfg.preview_lines or 0
  local layout = Board.calculate_layout(num_cols, nil, nil, preview_lines)
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
  end

  self:_setup_autocommands()
end

--- Populate existing loading windows with real data in-place.
--- Sets up navigation and full keymaps.
---@param data table Board data from api.fetch_all_columns
function Board:populate(data)
  self.data = data
  local cols = build_column_list(data)

  -- If column count doesn't match windows, fall back to close+open
  if #cols ~= #self.windows then
    self:close()
    self:open(data)
    return
  end

  if #cols == 0 then
    self:close()
    utils.notify("No columns to display", vim.log.levels.WARN)
    return
  end

  local cfg = config.get()
  local preview_lines = cfg.preview_lines or 0
  local layout = Board.calculate_layout(#cols, nil, nil, preview_lines)

  -- Fetch worktree map (sync, ~4ms) for card badges
  local wt_map = worktree.fetch_worktree_map()
  self.worktree_map = wt_map
  local sessions = claude.get_all_sessions()

  for i, col in ipairs(cols) do
    local buf = self.buffers[i]
    local win = self.windows[i]

    if buf and vim.api.nvim_buf_is_valid(buf) then
      local inner_width = layout.col_width - 2
      local lines, card_ranges = card.render_column(col.issues, inner_width, wt_map, sessions, self.sub_issue_counts)
      col.card_ranges = card_ranges

      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    end

    -- Update window title with count
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

  -- Apply orange highlight to active worktree cards
  self:_apply_active_highlights(wt_map)

  -- Enrich worktree map with dirty/clean status asynchronously
  worktree.fetch_enriched(function(enriched_map)
    if not self:is_open() then
      return
    end
    self.worktree_map = enriched_map
    -- Re-render columns with dirty/clean badges
    for i, col in ipairs(self.columns) do
      local buf = self.buffers[i]
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local inner_width = layout.col_width - 2
        local lines, card_ranges =
          card.render_column(col.issues, inner_width, enriched_map, sessions, self.sub_issue_counts)
        col.card_ranges = card_ranges
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
      end
    end
    -- Re-apply active highlights after re-rendering
    self:_apply_active_highlights(enriched_map)
    -- Re-highlight current card and update preview
    if self.navigation then
      self.navigation:highlight_current()
    end
  end)

  -- Fetch sub-issue counts asynchronously
  local all_numbers = {}
  for _, col in ipairs(cols) do
    for _, issue in ipairs(col.issues) do
      table.insert(all_numbers, issue.number)
    end
  end
  if #all_numbers > 0 then
    local api = require("okuban.api")
    api.fetch_sub_issue_counts(all_numbers, function(counts)
      if not self:is_open() then
        return
      end
      if not counts or vim.tbl_isempty(counts) then
        return
      end
      self.sub_issue_counts = counts
      -- Re-render columns with sub-issue badges
      local re_sessions = claude.get_all_sessions()
      for i, col in ipairs(self.columns) do
        local buf = self.buffers[i]
        if buf and vim.api.nvim_buf_is_valid(buf) then
          local re_layout = Board.calculate_layout(#self.columns, nil, nil, cfg.preview_lines or 0)
          local iw = re_layout.col_width - 2
          local lines, card_ranges = card.render_column(col.issues, iw, self.worktree_map, re_sessions, counts)
          col.card_ranges = card_ranges
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modifiable = false
        end
      end
      if self.navigation then
        self.navigation:highlight_current()
      end
    end)
  end

  -- Set up or update navigation, preserving position during refresh
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

  self:_start_polling()
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
  local layout = Board.calculate_layout(#cols, nil, nil, preview_lines)
  self.augroup = vim.api.nvim_create_augroup("OkubanBoard", { clear = true })

  -- Create header bar above columns
  header.create(layout)

  -- Fetch worktree map for card badges
  local wt_map = worktree.fetch_worktree_map()
  self.worktree_map = wt_map
  local sessions = claude.get_all_sessions()

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
  self:_start_polling()
end

--- Reposition all windows after a resize.
function Board:_reposition()
  if #self.windows == 0 then
    return
  end

  local cfg = config.get()
  local preview_lines = cfg.preview_lines or 0
  local num_cols = #self.windows
  local layout = Board.calculate_layout(num_cols, nil, nil, preview_lines)

  for i, win in ipairs(self.windows) do
    if vim.api.nvim_win_is_valid(win) then
      local col_offset = (i - 1) * (layout.col_width + layout.gap)
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = layout.start_row,
        col = layout.start_col + col_offset,
        width = layout.col_width,
        height = layout.board_height,
      })
    end
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

  -- Update scroll indicators after resize (window height may have changed)
  if self.navigation then
    self.navigation:update_scroll_indicators()
  end
end

--- Close the board and clean up all windows and buffers.
function Board:close()
  self:_stop_polling()

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

return Board

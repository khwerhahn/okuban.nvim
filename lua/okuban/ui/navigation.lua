local config = require("okuban.config")

local Navigation = {}
Navigation.__index = Navigation

local ns_id = vim.api.nvim_create_namespace("okuban_card_focus")

--- Create a new Navigation instance attached to a board.
---@param board table Board instance
---@return table
function Navigation.new(board)
  local o = setmetatable({}, Navigation)
  o.board = board
  o.column_index = 1
  o.card_index = 1
  o.issue_mode = false
  o._expanding = false
  o._tree_sub_index = 0
  return o
end

--- Get the number of cards in a column.
---@param col_idx integer
---@return integer
function Navigation:card_count(col_idx)
  local col = self.board.columns[col_idx]
  if not col then
    return 0
  end
  return #col.issues
end

--- Get the total number of columns.
---@return integer
function Navigation:num_columns()
  return #self.board.columns
end

--- Move to the next column (right).
function Navigation:move_right()
  if self.column_index < self:num_columns() then
    -- Collapse any tree expansion and exit issue mode before changing column
    local tree = require("okuban.ui.tree")
    if tree.is_expanded(self.column_index, self:_current_parent_number()) or self._tree_sub_index > 0 then
      tree.collapse_all(self.column_index)
      self._tree_sub_index = 0
      self.board:_restore_column_widths()
      self:_rerender_column(self.column_index)
    end
    if self.issue_mode then
      self:toggle_issue_mode()
    end

    self.column_index = self.column_index + 1
    -- Clamp card_index to new column's size
    local count = self:card_count(self.column_index)
    if count == 0 then
      self.card_index = 1
    elseif self.card_index > count then
      self.card_index = count
    end
    self:_focus_window()
    self:highlight_current()
  end
end

--- Move to the previous column (left).
function Navigation:move_left()
  if self.column_index > 1 then
    -- Collapse any tree expansion and exit issue mode before changing column
    local tree = require("okuban.ui.tree")
    if tree.is_expanded(self.column_index, self:_current_parent_number()) or self._tree_sub_index > 0 then
      tree.collapse_all(self.column_index)
      self._tree_sub_index = 0
      self.board:_restore_column_widths()
      self:_rerender_column(self.column_index)
    end
    if self.issue_mode then
      self:toggle_issue_mode()
    end

    self.column_index = self.column_index - 1
    local count = self:card_count(self.column_index)
    if count == 0 then
      self.card_index = 1
    elseif self.card_index > count then
      self.card_index = count
    end
    self:_focus_window()
    self:highlight_current()
  end
end

--- Move to the next card (down).
function Navigation:move_down()
  local tree = require("okuban.ui.tree")
  local parent_num = self:_current_parent_number()

  -- Tree navigation: entering or moving within sub-issues
  if
    parent_num
    and tree.is_expanded(self.column_index, parent_num)
    and not tree.is_loading(self.column_index, parent_num)
  then
    local subs = tree.get_cached(parent_num)
    if subs and #subs > 0 then
      if self._tree_sub_index == 0 then
        -- Enter sub-issues from parent card
        self._tree_sub_index = 1
        self:highlight_current()
        return
      elseif self._tree_sub_index < #subs then
        -- Move to next sub-issue
        self._tree_sub_index = self._tree_sub_index + 1
        self:highlight_current()
        return
      else
        -- Past last sub-issue: collapse, restore widths, move to next card
        tree.collapse(self.column_index, parent_num)
        self._tree_sub_index = 0
        self.board:_restore_column_widths()
        self:_rerender_column(self.column_index)
        -- Fall through to normal move_down logic
      end
    end
  end

  local count = self:card_count(self.column_index)
  if self.card_index < count then
    self.card_index = self.card_index + 1
    self:highlight_current()
  elseif count > 0 and not self._expanding then
    -- At boundary: check if column has more to load
    local col = self.board.columns and self.board.columns[self.column_index]
    if col and col.has_more then
      self:_trigger_expand()
    end
  end
end

--- Move to the previous card (up).
function Navigation:move_up()
  -- Tree navigation: moving within sub-issues
  if self._tree_sub_index > 1 then
    self._tree_sub_index = self._tree_sub_index - 1
    self:highlight_current()
    return
  elseif self._tree_sub_index == 1 then
    -- Back to parent card
    self._tree_sub_index = 0
    self:highlight_current()
    return
  end

  if self.card_index > 1 then
    self.card_index = self.card_index - 1
    self:highlight_current()
  end
end

--- Get the issue number of the current parent card (for tree operations).
---@return integer|nil
function Navigation:_current_parent_number()
  local issue = self:get_selected_issue()
  return issue and issue.number or nil
end

--- Toggle sub-issue tree expansion on the current card.
--- If the card has sub-issues: expand/collapse the tree.
--- If no sub-issues: just toggle issue mode.
function Navigation:toggle_tree()
  local issue = self:get_selected_issue()
  if not issue then
    local utils = require("okuban.utils")
    utils.notify("No issue selected", vim.log.levels.WARN)
    return
  end

  -- If we're on a sub-issue, ignore (sub-issues are display-only)
  if self._tree_sub_index > 0 then
    return
  end

  local tree = require("okuban.ui.tree")
  local col_idx = self.column_index
  local parent_num = issue.number

  -- Check if this card has sub-issues (board-level map for labels mode,
  -- issue-embedded counts for project mode)
  local sub_count_info = (self.board.sub_issue_counts and self.board.sub_issue_counts[parent_num])
    or issue.sub_issue_counts
  local has_subs = sub_count_info and sub_count_info.total and sub_count_info.total > 0

  if not has_subs then
    -- No sub-issues: just toggle issue mode (existing behavior)
    self:toggle_issue_mode()
    return
  end

  -- If already expanded: collapse and restore column widths
  if tree.is_expanded(col_idx, parent_num) then
    tree.collapse(col_idx, parent_num)
    self._tree_sub_index = 0
    self.board:_restore_column_widths()
    self:_rerender_column(col_idx)
    if self.issue_mode then
      self:toggle_issue_mode()
    end
    self:highlight_current()
    return
  end

  -- Enter issue mode if not already
  if not self.issue_mode then
    self:toggle_issue_mode()
  end

  -- Expand the column visually before rendering tree content
  self.board:_apply_column_expansion(col_idx)

  -- Check cache first
  local cached = tree.get_cached(parent_num)
  if cached then
    tree.set_expanded(col_idx, parent_num, cached)
    self:_rerender_column(col_idx)
    self:highlight_current()
    return
  end

  -- Fetch sub-issues asynchronously
  tree.set_loading(col_idx, parent_num)
  self:_rerender_column(col_idx)
  self:highlight_current()

  local api = require("okuban.api")
  api.fetch_sub_issues(parent_num, function(subs)
    if not self.board:is_open() then
      return
    end
    -- Verify we're still on the same card
    if self.column_index ~= col_idx or self:_current_parent_number() ~= parent_num then
      tree.collapse(col_idx, parent_num)
      self.board:_restore_column_widths()
      return
    end
    tree.set_expanded(col_idx, parent_num, subs or {})
    self:_rerender_column(col_idx)
    self:highlight_current()
  end)
end

--- Re-render a single column buffer with tree-aware visible items.
---@param col_idx integer
function Navigation:_rerender_column(col_idx)
  local col = self.board.columns[col_idx]
  local buf = self.board.buffers[col_idx]
  if not col or not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local tree = require("okuban.ui.tree")
  local card_mod = require("okuban.ui.card")
  local claude = require("okuban.claude")

  if not self.board._layout then
    return
  end
  local col_width = self.board:get_column_width(col_idx)
  local inner_width = col_width - 2
  local sessions = claude.get_all_sessions()
  local wt_map = self.board.worktree_map

  local visible = tree.build_visible_items(col, col_idx)
  local lines = {}
  local card_ranges = {}

  for _, item in ipairs(visible) do
    if item.type == "card" then
      local line = card_mod.render_card(item.issue, inner_width, wt_map, sessions, self.board.sub_issue_counts)
      table.insert(lines, line)
      card_ranges[item.card_idx] = { start_line = #lines, end_line = #lines }
    elseif item.type == "sub_issue" then
      table.insert(lines, tree.render_sub_issue_line(item.sub, item.is_last, inner_width))
    elseif item.type == "loading" then
      table.insert(lines, tree.render_loading_line(inner_width))
    end
  end

  if #lines == 0 then
    lines = { "  (no issues)" }
  end

  col.card_ranges = card_ranges
  col._visible_items = visible

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Get the currently selected sub-issue (if navigating within a tree).
---@return table|nil sub_issue
function Navigation:_get_selected_sub()
  if self._tree_sub_index <= 0 then
    return nil
  end
  local tree = require("okuban.ui.tree")
  local parent_num = self:_current_parent_number()
  if not parent_num then
    return nil
  end
  local cached = tree.get_cached(parent_num)
  if not cached then
    return nil
  end
  return cached[self._tree_sub_index]
end

--- Trigger lazy expansion of the current column.
--- Shows a loading footer and fetches more issues via api.expand_column.
function Navigation:_trigger_expand()
  local col_index = self.column_index
  local win = self.board.windows[col_index]

  -- Show loading footer
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_config, win, {
      footer = " \xe2\x86\x93 loading... ",
      footer_pos = "center",
    })
  end

  self._expanding = true
  local api = require("okuban.api")
  api.expand_column(col_index, function(ok, err)
    self._expanding = false
    if not ok then
      local utils = require("okuban.utils")
      utils.notify("Failed to load more: " .. (err or ""), vim.log.levels.WARN)
      self:update_scroll_indicators()
      return
    end
    -- Refresh board with expanded data
    if self.board.data and self.board:is_open() then
      self.board:refresh(self.board.data)
    end
  end)
end

--- Focus the window corresponding to the current column.
function Navigation:_focus_window()
  local win = self.board.windows[self.column_index]
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

--- Highlight the currently focused card using extmarks.
--- Supports multi-line cards via card_ranges on each column.
--- When _tree_sub_index > 0, highlights the sub-issue line instead.
function Navigation:highlight_current()
  -- Clear all highlights in all board buffers
  for _, buf in ipairs(self.board.buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    end
  end

  -- Add highlight to the current card
  local buf = self.board.buffers[self.column_index]
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local col = self.board.columns[self.column_index]
  local ranges = col and col.card_ranges
  local line_count = vim.api.nvim_buf_line_count(buf)
  local win = self.board.windows[self.column_index]

  -- Sub-issue highlight: find the buffer line for the sub-issue
  if self._tree_sub_index > 0 and col and col._visible_items then
    local target_line = self:_find_sub_issue_line(col._visible_items)
    if target_line and target_line > 0 and target_line <= line_count then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "OkubanCardFocused", target_line - 1, 0, -1)
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_cursor(win, { target_line, 0 })
      end
    end

    -- Update preview with sub-issue content
    local sub = self:_get_selected_sub()
    if sub and self.board.update_preview then
      self.board:update_preview(sub)
    end

    self:update_scroll_indicators()
    return
  end

  if ranges and ranges[self.card_index] then
    -- Multi-line card: highlight entire range
    local range = ranges[self.card_index]
    for line_nr = range.start_line, range.end_line do
      local zero_line = line_nr - 1
      if zero_line >= 0 and zero_line < line_count then
        vim.api.nvim_buf_add_highlight(buf, ns_id, "OkubanCardFocused", zero_line, 0, -1)
      end
    end

    -- Scroll into view: set cursor to end_line first (forces scroll), then start_line
    if win and vim.api.nvim_win_is_valid(win) then
      local end_row = math.min(range.end_line, line_count)
      vim.api.nvim_win_set_cursor(win, { end_row, 0 })
      vim.api.nvim_win_set_cursor(win, { range.start_line, 0 })
    end
  else
    -- Fallback: single-line mode (legacy or no card_ranges)
    local line = self.card_index - 1
    if line >= 0 and line < line_count then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "OkubanCardFocused", line, 0, -1)
    end
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { self.card_index, 0 })
    end
  end

  -- Update preview pane with selected issue
  local issue = self:get_selected_issue()
  if self.board.update_preview then
    self.board:update_preview(issue)
  end

  -- Update header when in issue mode
  if self.issue_mode and issue then
    local header = require("okuban.ui.header")
    header.enter_issue_mode(issue)
  end

  -- Update scroll indicators on all column windows
  self:update_scroll_indicators()
end

--- Find the buffer line number for the current sub-issue in visible items.
---@param visible_items table[]
---@return integer|nil line 1-indexed buffer line
function Navigation:_find_sub_issue_line(visible_items)
  local parent_num = self:_current_parent_number()
  if not parent_num then
    return nil
  end
  local buf_line = 0
  for _, item in ipairs(visible_items) do
    buf_line = buf_line + 1
    if item.type == "sub_issue" and item.parent_idx == self.card_index and item.position == self._tree_sub_index then
      return buf_line
    end
  end
  return nil
end

--- Update scroll indicator footers on all column windows.
--- Shows "N more" when lines overflow below, "N" when scrolled past top.
--- Uses actual buffer line count (accounts for tree-expanded items).
function Navigation:update_scroll_indicators()
  for i, win in ipairs(self.board.windows) do
    if not win or not vim.api.nvim_win_is_valid(win) then
      goto continue
    end

    local buf = self.board.buffers[i]
    local total_lines = buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_line_count(buf) or 0
    if total_lines == 0 then
      pcall(vim.api.nvim_win_set_config, win, { footer = "" })
      goto continue
    end

    local win_height = vim.api.nvim_win_get_height(win)
    if total_lines <= win_height then
      pcall(vim.api.nvim_win_set_config, win, { footer = "" })
    else
      local first_visible = vim.fn.line("w0", win)
      local last_visible = vim.fn.line("w$", win)
      local above = first_visible - 1
      local below = total_lines - last_visible

      local parts = {}
      if above > 0 then
        table.insert(parts, "\xe2\x86\x91 " .. above)
      end
      if below > 0 then
        table.insert(parts, "\xe2\x86\x93 " .. below .. " more")
      end

      if #parts > 0 then
        local footer = " " .. table.concat(parts, "  ") .. " "
        pcall(vim.api.nvim_win_set_config, win, { footer = footer, footer_pos = "center" })
      else
        pcall(vim.api.nvim_win_set_config, win, { footer = "" })
      end
    end

    ::continue::
  end
end

--- Navigate to the card matching the given issue number.
--- Searches all columns and sets column_index + card_index accordingly.
---@param issue_number integer
---@return boolean found True if the issue was found and focused
function Navigation:focus_issue(issue_number)
  for col_idx, col in ipairs(self.board.columns) do
    for card_idx, issue in ipairs(col.issues) do
      if issue.number == issue_number then
        self.column_index = col_idx
        self.card_index = card_idx
        self._tree_sub_index = 0
        self:_focus_window()
        self:highlight_current()
        return true
      end
    end
  end
  return false
end

--- Toggle issue mode on/off.
--- In issue mode, the header shows issue-specific actions (view, close, assign, code).
function Navigation:toggle_issue_mode()
  local hdr = require("okuban.ui.header")
  if self.issue_mode then
    self.issue_mode = false
    hdr.exit_issue_mode()
  else
    local issue = self:get_selected_issue()
    if not issue then
      local utils = require("okuban.utils")
      utils.notify("No issue selected", vim.log.levels.WARN)
      return
    end
    self.issue_mode = true
    hdr.enter_issue_mode(issue)
  end
end

--- Get the issue data for the currently selected card.
---@return table|nil issue
function Navigation:get_selected_issue()
  local col = self.board.columns[self.column_index]
  if not col then
    return nil
  end
  return col.issues[self.card_index]
end

--- Get the label of the currently selected column.
---@return string|nil
function Navigation:get_selected_column_label()
  local col = self.board.columns[self.column_index]
  if not col then
    return nil
  end
  -- data.columns have label field, unsorted column does not
  local board_col = self.board.data and self.board.data.columns[self.column_index]
  return board_col and board_col.label or nil
end

--- Set up keymaps on a board buffer.
---@param buf integer Buffer handle
function Navigation:setup_keymaps(buf)
  local keymaps = config.get().keymaps
  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", keymaps.column_left, function()
    self:move_left()
  end, opts)

  vim.keymap.set("n", keymaps.column_right, function()
    self:move_right()
  end, opts)

  vim.keymap.set("n", keymaps.card_up, function()
    self:move_up()
  end, opts)

  vim.keymap.set("n", keymaps.card_down, function()
    self:move_down()
  end, opts)

  -- Arrow keys always mirror hjkl navigation (supplementary, not configurable)
  vim.keymap.set("n", "<Left>", function()
    self:move_left()
  end, opts)
  vim.keymap.set("n", "<Right>", function()
    self:move_right()
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    self:move_up()
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    self:move_down()
  end, opts)

  vim.keymap.set("n", keymaps.close, function()
    self.board:close()
  end, opts)

  -- Esc: collapse tree → exit issue mode → close board (cascade)
  if keymaps.close ~= "<Esc>" then
    vim.keymap.set("n", "<Esc>", function()
      local tree = require("okuban.ui.tree")
      local parent_num = self:_current_parent_number()
      if parent_num and tree.is_expanded(self.column_index, parent_num) then
        tree.collapse(self.column_index, parent_num)
        self._tree_sub_index = 0
        self.board:_restore_column_widths()
        self:_rerender_column(self.column_index)
        self:highlight_current()
      elseif self.issue_mode then
        self:toggle_issue_mode()
      else
        self.board:close()
      end
    end, opts)
  end

  vim.keymap.set("n", keymaps.refresh, function()
    local api = require("okuban.api")
    api.fetch_all_columns(function(data)
      if data then
        self.board:refresh(data)
        -- Reset the limited auto-refresh cycle on manual refresh
        self.board:_start_auto_refresh()
      end
    end)
  end, opts)

  vim.keymap.set("n", keymaps.move_card, function()
    local move = require("okuban.ui.move")
    move.prompt_move(self.board)
  end, opts)

  -- Enter: toggle tree expansion (or issue mode if no sub-issues)
  vim.keymap.set("n", keymaps.open_actions, function()
    self:toggle_tree()
  end, opts)

  -- Issue-mode action keymaps (v, c, a, x)
  local action_keys = { "v", "c", "a", "x" }
  for _, key in ipairs(action_keys) do
    vim.keymap.set("n", key, function()
      if not self.issue_mode then
        return
      end
      -- Sub-issue context: only 'v' (view in browser) is allowed
      if self._tree_sub_index > 0 then
        if key == "v" then
          local sub = self:_get_selected_sub()
          if sub and sub.number then
            local api = require("okuban.api")
            api.view_issue_in_browser(sub.number)
            local utils = require("okuban.utils")
            utils.notify("Opening #" .. sub.number .. " in browser")
          end
        end
        return
      end
      local issue = self:get_selected_issue()
      if not issue then
        return
      end
      local actions = require("okuban.ui.actions")
      actions.execute_action(key, issue, self.board)
    end, opts)
  end

  vim.keymap.set("n", keymaps.new_issue, function()
    local create = require("okuban.ui.create")
    create.open(self.board)
  end, opts)

  vim.keymap.set("n", keymaps.help, function()
    local help = require("okuban.ui.help")
    help.open()
  end, opts)

  vim.keymap.set("n", keymaps.goto_current, function()
    local detect = require("okuban.detect")
    local utils = require("okuban.utils")
    detect.detect_issue(function(issue_number)
      if not issue_number then
        utils.notify("No current issue detected", vim.log.levels.WARN)
        return
      end
      local found = self:focus_issue(issue_number)
      if found then
        local issue = self:get_selected_issue()
        local title = issue and issue.title or ""
        utils.notify("Focused on #" .. issue_number .. ": " .. title)
      else
        utils.notify("#" .. issue_number .. " not on the board", vim.log.levels.WARN)
      end
    end)
  end, opts)

  -- In-board command shortcuts (disabled in issue mode to avoid key conflicts)
  vim.keymap.set("n", keymaps.setup_labels, function()
    if not self.issue_mode then
      vim.cmd("OkubanSetup")
    end
  end, opts)

  vim.keymap.set("n", keymaps.switch_source, function()
    if not self.issue_mode then
      local cfg = config.get()
      local current = cfg.source
      local target = current == "labels" and "project" or "labels"
      vim.cmd("OkubanSource " .. target)
    end
  end, opts)

  vim.keymap.set("n", keymaps.triage, function()
    if not self.issue_mode then
      vim.cmd("OkubanTriage")
    end
  end, opts)
end

return Navigation

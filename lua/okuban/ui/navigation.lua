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
  local count = self:card_count(self.column_index)
  if self.card_index < count then
    self.card_index = self.card_index + 1
    self:highlight_current()
  end
end

--- Move to the previous card (up).
function Navigation:move_up()
  if self.card_index > 1 then
    self.card_index = self.card_index - 1
    self:highlight_current()
  end
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

--- Update scroll indicator footers on all column windows.
--- Shows "↓ N more" when cards overflow below, "↑ N" when scrolled past top.
--- Uses partial nvim_win_set_config (valid in Neovim 0.10+: absent keys are unchanged).
function Navigation:update_scroll_indicators()
  for i, win in ipairs(self.board.windows) do
    if not win or not vim.api.nvim_win_is_valid(win) then
      goto continue
    end

    local total_cards = self:card_count(i)
    if total_cards == 0 then
      pcall(vim.api.nvim_win_set_config, win, { footer = "" })
      goto continue
    end

    local win_height = vim.api.nvim_win_get_height(win)
    if total_cards <= win_height then
      pcall(vim.api.nvim_win_set_config, win, { footer = "" })
    else
      local first_visible = vim.fn.line("w0", win)
      local last_visible = vim.fn.line("w$", win)
      local above = first_visible - 1
      local below = total_cards - last_visible

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

  vim.keymap.set("n", keymaps.close, function()
    self.board:close()
  end, opts)

  -- Esc: exit issue mode first, then close board
  if keymaps.close ~= "<Esc>" then
    vim.keymap.set("n", "<Esc>", function()
      if self.issue_mode then
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
      end
    end)
  end, opts)

  vim.keymap.set("n", keymaps.move_card, function()
    local move = require("okuban.ui.move")
    move.prompt_move(self.board)
  end, opts)

  -- Enter: toggle issue mode (replaces action menu popup)
  vim.keymap.set("n", keymaps.open_actions, function()
    self:toggle_issue_mode()
  end, opts)

  -- Issue-mode action keymaps (v, c, a, x)
  local action_keys = { "v", "c", "a", "x" }
  for _, key in ipairs(action_keys) do
    vim.keymap.set("n", key, function()
      if not self.issue_mode then
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
end

return Navigation

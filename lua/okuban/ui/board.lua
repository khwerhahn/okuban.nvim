local card = require("okuban.ui.card")
local utils = require("okuban.utils")

local Board = {}
Board.__index = Board

-- Singleton instance
local instance = nil

--- Highlight groups with sensible defaults.
local function define_highlights()
  vim.api.nvim_set_hl(0, "OkubanCardFocused", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "OkubanColumnHeader", { default = true, link = "Title" })
end

--- Calculate layout dimensions for the board.
---@param num_cols integer
---@param screen_width integer|nil
---@param screen_height integer|nil
---@return table { board_width, board_height, col_width, start_row, start_col, gap }
function Board.calculate_layout(num_cols, screen_width, screen_height)
  local sw = screen_width or vim.o.columns
  local sh = screen_height or vim.o.lines

  local board_width = math.floor(sw * 0.9)
  local board_height = math.floor(sh * 0.8)
  local gap = 1
  local col_width = math.floor((board_width - (num_cols - 1) * gap) / num_cols)

  -- Enforce minimum column width
  local min_col_width = 20
  if col_width < min_col_width then
    col_width = min_col_width
    board_width = num_cols * col_width + (num_cols - 1) * gap
  end

  local start_row = math.floor((sh - board_height) / 2)
  local start_col = math.floor((sw - board_width) / 2)

  return {
    board_width = board_width,
    board_height = board_height,
    col_width = col_width,
    start_row = start_row,
    start_col = start_col,
    gap = gap,
  }
end

--- Create a new Board instance.
---@return table
function Board.new()
  local o = setmetatable({}, Board)
  o.windows = {}
  o.buffers = {}
  o.data = nil
  o.augroup = nil
  return o
end

--- Open the board with the given data.
---@param data table Board data from api.fetch_all_columns
function Board:open(data)
  self.data = data
  define_highlights()

  -- Build the column list for rendering
  local cols = {}
  for _, col in ipairs(data.columns) do
    table.insert(cols, { name = col.name, issues = col.issues })
  end
  if data.unsorted and #data.unsorted > 0 then
    table.insert(cols, { name = "Unsorted", issues = data.unsorted })
  end

  if #cols == 0 then
    utils.notify("No columns to display", vim.log.levels.WARN)
    return
  end

  local layout = Board.calculate_layout(#cols)

  -- Create autocommand group for this board
  self.augroup = vim.api.nvim_create_augroup("OkubanBoard", { clear = true })

  -- Create one floating window per column
  for i, col in ipairs(cols) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "okuban"

    -- Render cards into the buffer
    local inner_width = layout.col_width - 2 -- account for border
    local lines = card.render_column(col.issues, inner_width)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- Calculate window position
    local col_offset = (i - 1) * (layout.col_width + layout.gap)
    local win_col = layout.start_col + col_offset

    local title = string.format(" %s (%d) ", col.name, #col.issues)
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

    -- Set window options
    vim.wo[win].cursorline = false
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"

    table.insert(self.windows, win)
    table.insert(self.buffers, buf)
  end

  -- Store column metadata for navigation
  self.columns = cols

  -- Set up navigation
  local Navigation = require("okuban.ui.navigation")
  self.navigation = Navigation.new(self)
  for _, buf in ipairs(self.buffers) do
    self.navigation:setup_keymaps(buf)
  end
  self.navigation:highlight_current()

  -- VimResized handler
  vim.api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      self:_reposition()
    end,
  })

  -- WinClosed handler — if any board window is closed externally, clean up all
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    callback = function(ev)
      local closed_win = tonumber(ev.match)
      for _, w in ipairs(self.windows) do
        if w == closed_win then
          -- Defer to avoid issues during WinClosed
          vim.schedule(function()
            self:close()
          end)
          return
        end
      end
    end,
  })
end

--- Reposition all windows after a resize.
function Board:_reposition()
  if #self.windows == 0 then
    return
  end

  local num_cols = #self.windows
  local layout = Board.calculate_layout(num_cols)

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
end

--- Close the board and clean up all windows and buffers.
function Board:close()
  if self.augroup then
    vim.api.nvim_del_augroup_by_id(self.augroup)
    self.augroup = nil
  end

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
---@param data table Board data from api.fetch_all_columns
function Board:refresh(data)
  self:close()
  self:open(data)
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

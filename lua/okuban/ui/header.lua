local config = require("okuban.config")

local M = {}

M.MODE_DEFAULT = "default"
M.MODE_ISSUE = "issue"

local header_win = nil
local header_buf = nil
local current_mode = M.MODE_DEFAULT
local current_issue = nil
local stored_width = nil
local _last_updated_at = nil
local _staleness_timer = nil

--- Format elapsed time since last update as a human-readable string.
---@param ts integer|nil os.time() timestamp
---@return string|nil
function M._format_staleness(ts)
  if not ts then
    return nil
  end
  local elapsed = os.time() - ts
  if elapsed < 10 then
    return "just now"
  end
  if elapsed < 60 then
    return elapsed .. "s ago"
  end
  if elapsed < 3600 then
    return math.floor(elapsed / 60) .. "m ago"
  end
  return math.floor(elapsed / 3600) .. "h ago"
end

--- Render header content lines based on mode.
---@param mode string
---@param issue table|nil
---@return string[]
function M._render(mode, issue)
  local width = stored_width or 100
  local inner_width = width - 2

  if mode == M.MODE_ISSUE and issue then
    local parts = { " [Esc] Back  [m] Move  [v] View" }
    local is_open = issue.state ~= "CLOSED"
    if is_open then
      table.insert(parts, "  [c] Close  [a] Assign")
    end
    local claude_cfg = config.get().claude
    if claude_cfg.enabled then
      local ok, claude_mod = pcall(require, "okuban.claude")
      if ok and claude_mod.is_available() then
        table.insert(parts, "  [x] Code")
      end
    end
    local prefix = table.concat(parts, "")
    local separator = "  │  "
    local title = string.format("#%d: %s", issue.number, issue.title or "Untitled")
    local title_space = width - #prefix - #separator - 2
    if title_space > 0 and #title > title_space then
      title = title:sub(1, title_space - 3) .. "..."
    end
    return { prefix .. separator .. title }
  else
    local left = " [Enter] Actions  [m] Move  [n] New  [g] Goto  [s] Source  [r] Refresh  [?] Help  [q] Close"
    local staleness = M._format_staleness(_last_updated_at)
    if staleness then
      local right = staleness .. " "
      local padding = inner_width - #left - #right
      if padding > 2 then
        return { left .. string.rep(" ", padding) .. right }
      end
    end
    return { left }
  end
end

--- Create the header floating window.
---@param layout table Layout from Board.calculate_layout
function M.create(layout)
  if header_win and vim.api.nvim_win_is_valid(header_win) then
    return
  end

  stored_width = layout.board_width

  header_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[header_buf].buftype = "nofile"
  vim.bo[header_buf].bufhidden = "wipe"
  vim.bo[header_buf].swapfile = false
  vim.bo[header_buf].filetype = "okuban"

  local lines = M._render(M.MODE_DEFAULT, nil)
  vim.api.nvim_buf_set_lines(header_buf, 0, -1, false, lines)
  vim.bo[header_buf].modifiable = false

  header_win = vim.api.nvim_open_win(header_buf, false, {
    relative = "editor",
    row = layout.header_row,
    col = layout.start_col,
    width = layout.board_width,
    height = layout.header_height,
    style = "minimal",
    border = "rounded",
    title = " okuban ",
    title_pos = "center",
    focusable = false,
    zindex = 50,
  })

  vim.wo[header_win].cursorline = false
  vim.wo[header_win].wrap = false
  vim.wo[header_win].number = false
  vim.wo[header_win].relativenumber = false
  vim.wo[header_win].signcolumn = "no"

  current_mode = M.MODE_DEFAULT
  current_issue = nil
end

--- Update header content for the given mode and issue.
---@param mode string
---@param issue table|nil
function M.update(mode, issue)
  if not header_buf or not vim.api.nvim_buf_is_valid(header_buf) then
    return
  end
  current_mode = mode
  current_issue = issue
  local lines = M._render(mode, issue)
  vim.bo[header_buf].modifiable = true
  vim.api.nvim_buf_set_lines(header_buf, 0, -1, false, lines)
  vim.bo[header_buf].modifiable = false
end

--- Get the current header mode.
---@return string
function M.get_mode()
  return current_mode
end

--- Check if header is in issue mode.
---@return boolean
function M.is_issue_mode()
  return current_mode == M.MODE_ISSUE
end

--- Enter issue mode for the given issue.
---@param issue table
function M.enter_issue_mode(issue)
  M.update(M.MODE_ISSUE, issue)
end

--- Exit issue mode back to default.
function M.exit_issue_mode()
  M.update(M.MODE_DEFAULT, nil)
end

--- Record the time of the last data update and start the staleness timer.
---@param ts integer os.time() timestamp
function M.set_last_updated(ts)
  _last_updated_at = ts
  -- Re-render header to show fresh staleness text
  M.update(current_mode, current_issue)
  M._start_staleness_timer()
end

--- Start (or restart) the 10-second staleness display timer.
function M._start_staleness_timer()
  M._stop_staleness_timer()
  local timer = vim.uv.new_timer()
  timer:start(
    10000,
    10000,
    vim.schedule_wrap(function()
      -- Re-render header to update staleness text
      if header_buf and vim.api.nvim_buf_is_valid(header_buf) then
        M.update(current_mode, current_issue)
      end
    end)
  )
  _staleness_timer = timer
end

--- Stop the staleness display timer.
function M._stop_staleness_timer()
  if _staleness_timer then
    _staleness_timer:stop()
    _staleness_timer:close()
    _staleness_timer = nil
  end
end

--- Close the header window and clean up.
function M.close()
  M._stop_staleness_timer()
  if header_win and vim.api.nvim_win_is_valid(header_win) then
    vim.api.nvim_win_close(header_win, true)
  end
  header_win = nil
  header_buf = nil
  current_mode = M.MODE_DEFAULT
  current_issue = nil
  stored_width = nil
  _last_updated_at = nil
end

--- Reposition the header window after a resize.
---@param layout table Layout from Board.calculate_layout
function M.reposition(layout)
  if not header_win or not vim.api.nvim_win_is_valid(header_win) then
    return
  end
  stored_width = layout.board_width
  vim.api.nvim_win_set_config(header_win, {
    relative = "editor",
    row = layout.header_row,
    col = layout.start_col,
    width = layout.board_width,
    height = layout.header_height,
  })
  -- Re-render to fit new width
  M.update(current_mode, current_issue)
end

--- Get the header window handle (for autocommand checks).
---@return integer|nil
function M.get_win()
  return header_win
end

--- Get the last updated timestamp (for tests).
---@return integer|nil
function M.get_last_updated()
  return _last_updated_at
end

--- Reset state (for tests).
function M._reset()
  M._stop_staleness_timer()
  header_win = nil
  header_buf = nil
  current_mode = M.MODE_DEFAULT
  current_issue = nil
  stored_width = nil
  _last_updated_at = nil
end

return M

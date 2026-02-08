local M = {}

--- Send a notification with the okuban prefix.
---@param msg string
---@param level integer|nil vim.log.levels value (default: INFO)
function M.notify(msg, level)
  vim.notify("okuban: " .. msg, level or vim.log.levels.INFO)
end

--- Check if an executable is available on PATH.
---@param name string
---@return boolean
function M.is_executable(name)
  return vim.fn.executable(name) == 1
end

-- ---------------------------------------------------------------------------
-- Spinner — persistent floating progress indicator
-- ---------------------------------------------------------------------------

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local active_spinner = nil

--- Start a persistent spinner with a message.
--- Returns a function to update or stop the spinner.
---@param msg string Initial message
---@return fun(done_msg: string|nil) Call with a string to show final message and stop, or nil to just stop
function M.spinner_start(msg)
  -- Stop any existing spinner
  if active_spinner then
    M._spinner_cleanup()
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local frame_idx = 1
  local current_msg = msg
  local width = math.min(#msg + 4, 60)

  -- Position: bottom-right of the editor
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = vim.o.lines - 4,
    col = vim.o.columns - width - 3,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 100,
    noautocmd = true,
  })
  vim.wo[win].winblend = 10

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local frame = spinner_frames[frame_idx]
    local line = " " .. frame .. " " .. current_msg
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.bo[buf].modifiable = false
  end

  render()

  local timer = vim.uv.new_timer()
  timer:start(
    80,
    80,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        return
      end
      frame_idx = (frame_idx % #spinner_frames) + 1
      render()
    end)
  )

  active_spinner = { buf = buf, win = win, timer = timer }

  --- Stop the spinner, optionally showing a final message.
  ---@param done_msg string|nil
  return function(done_msg)
    if done_msg then
      M.notify(done_msg)
    end
    M._spinner_cleanup()
  end
end

--- Update the message of the active spinner.
---@param msg string
function M.spinner_update(msg)
  if not active_spinner or not vim.api.nvim_buf_is_valid(active_spinner.buf) then
    return
  end
  -- Resize window if needed
  local width = math.min(#msg + 4, 60)
  if vim.api.nvim_win_is_valid(active_spinner.win) then
    vim.api.nvim_win_set_config(active_spinner.win, {
      relative = "editor",
      row = vim.o.lines - 4,
      col = vim.o.columns - width - 3,
      width = width,
      height = 1,
    })
  end
  -- Update the text (the timer render will pick up the new width)
  local frame = spinner_frames[1]
  local line = " " .. frame .. " " .. msg
  vim.bo[active_spinner.buf].modifiable = true
  vim.api.nvim_buf_set_lines(active_spinner.buf, 0, -1, false, { line })
  vim.bo[active_spinner.buf].modifiable = false
end

--- Clean up the active spinner.
function M._spinner_cleanup()
  if not active_spinner then
    return
  end
  local s = active_spinner
  active_spinner = nil
  if s.timer then
    s.timer:stop()
    if not s.timer:is_closing() then
      s.timer:close()
    end
  end
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
end

-- ---------------------------------------------------------------------------
-- Persistence — save/load per-repo state to Neovim data directory
-- ---------------------------------------------------------------------------

--- Get the state file path for the current working directory.
---@return string
function M.state_file_path()
  local cwd = vim.fn.getcwd()
  -- Sanitize path: replace non-alphanumeric chars with underscores
  local key = cwd:gsub("[^%w]", "_")
  local dir = vim.fn.stdpath("data") .. "/okuban"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. key .. ".json"
end

--- Save per-repo state to disk.
---@param state table { source?: string, project_number?: integer, project_owner?: string }
function M.save_state(state)
  local path = M.state_file_path()
  local ok, json = pcall(vim.json.encode, state)
  if not ok then
    return
  end
  local f = io.open(path, "w")
  if f then
    f:write(json)
    f:close()
  end
end

--- Load per-repo state from disk.
---@return table|nil
function M.load_state()
  local path = M.state_file_path()
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    return nil
  end
  local ok, state = pcall(vim.json.decode, content)
  if ok and type(state) == "table" then
    return state
  end
  return nil
end

return M

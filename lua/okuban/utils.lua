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

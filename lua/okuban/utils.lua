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

return M

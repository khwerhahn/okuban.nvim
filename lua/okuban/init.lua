local M = {}

local config = require("okuban.config")
local utils = require("okuban.utils")
local api = require("okuban.api")

--- Set up okuban with user options.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
end

--- Open the kanban board.
function M.open()
  api.preflight(function(ok)
    if not ok then
      return
    end
    utils.notify("Board opening not yet implemented", vim.log.levels.WARN)
  end)
end

--- Close the kanban board.
function M.close()
  utils.notify("Board not open", vim.log.levels.WARN)
end

--- Refresh the kanban board.
function M.refresh()
  utils.notify("Board not open", vim.log.levels.WARN)
end

--- Run label setup on the current repo.
---@param opts { full: boolean }
function M.setup_labels(opts) -- luacheck: no unused args
  utils.notify("Label setup not yet implemented", vim.log.levels.WARN)
end

return M

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
  local Board = require("okuban.ui.board")
  local board = Board.get_instance()

  -- If board is already open, close it first (toggle behavior)
  if board:is_open() then
    board:close()
    return
  end

  api.preflight(function(ok)
    if not ok then
      return
    end
    api.fetch_all_columns(function(data)
      if not data then
        utils.notify("Failed to fetch issues", vim.log.levels.ERROR)
        return
      end
      board:open(data)
    end)
  end)
end

--- Close the kanban board.
function M.close()
  local Board = require("okuban.ui.board")
  Board.close_instance()
end

--- Refresh the kanban board.
function M.refresh()
  local Board = require("okuban.ui.board")
  local board = Board.get_instance()
  if not board:is_open() then
    utils.notify("Board not open", vim.log.levels.WARN)
    return
  end
  api.fetch_all_columns(function(data)
    if not data then
      utils.notify("Failed to refresh", vim.log.levels.ERROR)
      return
    end
    board:refresh(data)
  end)
end

--- Run label setup on the current repo.
---@param opts { full: boolean }
function M.setup_labels(opts)
  api.preflight(function(ok)
    if not ok then
      return
    end
    local full = opts and opts.full or false
    utils.notify("Creating labels" .. (full and " (full set)" or "") .. "...")
    api.create_all_labels(full, function(created, failed)
      if failed > 0 then
        utils.notify(string.format("Created %d labels, %d failed", created, failed), vim.log.levels.WARN)
      else
        utils.notify(string.format("Created %d labels", created))
      end
    end)
  end)
end

return M

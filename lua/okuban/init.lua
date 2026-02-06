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
    -- Show loading skeleton instantly, populate when data arrives
    board:open_loading()
    api.fetch_all_columns(function(data)
      if not data then
        utils.notify("Failed to fetch issues", vim.log.levels.ERROR)
        board:close()
        return
      end
      board:populate(data)

      -- First-open hint: if all kanban columns empty but unsorted has issues
      if not board._hint_shown then
        board._hint_shown = true
        local all_empty = true
        for _, col in ipairs(data.columns) do
          if #col.issues > 0 then
            all_empty = false
            break
          end
        end
        if all_empty and data.unsorted and #data.unsorted > 0 then
          utils.notify("Tip: press Enter on a card to triage it into a column, or m to move it directly")
        end
      end

      -- Auto-focus: detect current issue and navigate to it
      local detect = require("okuban.detect")
      detect.detect_issue(function(issue_number)
        if not issue_number or not board:is_open() or not board.navigation then
          return
        end
        local found = board.navigation:focus_issue(issue_number)
        if found then
          local issue = board.navigation:get_selected_issue()
          local title = issue and issue.title or ""
          utils.notify("Focused on #" .. issue_number .. ": " .. title)
        end
      end)
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

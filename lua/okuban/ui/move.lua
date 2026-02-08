local api = require("okuban.api")
local utils = require("okuban.utils")

local M = {}

--- Prompt the user to select a target column, then move the card.
---@param board table Board instance
function M.prompt_move(board)
  local nav = board.navigation
  if not nav then
    return
  end

  local issue = nav:get_selected_issue()
  if not issue then
    utils.notify("No issue selected", vim.log.levels.WARN)
    return
  end

  local current_label = nav:get_selected_column_label()
  if not current_label then
    utils.notify("Cannot move from this column", vim.log.levels.WARN)
    return
  end

  -- Build list of target columns from board data (works for both labels and project)
  local columns = board.data and board.data.columns or require("okuban.config").get().columns
  local targets = {}
  for _, col in ipairs(columns) do
    if col.label ~= current_label then
      table.insert(targets, col)
    end
  end

  if #targets == 0 then
    utils.notify("No target columns available", vim.log.levels.WARN)
    return
  end

  -- Build display names
  local names = {}
  for _, col in ipairs(targets) do
    table.insert(names, col.name)
  end

  vim.ui.select(names, { prompt = "Move #" .. issue.number .. " to:" }, function(choice)
    if not choice then
      return
    end

    -- Find the selected target column
    local target = nil
    for _, col in ipairs(targets) do
      if col.name == choice then
        target = col
        break
      end
    end

    if not target then
      return
    end

    M.execute_move(issue.number, current_label, target.label, target.name, board)
  end)
end

--- Execute the move and refresh the board.
--- In label mode: swaps labels. In project mode: updates Status field.
---@param number integer Issue number
---@param from_id string Current column identifier (label or status option ID)
---@param to_id string Target column identifier (label or status option ID)
---@param to_name string Target column display name
---@param board table Board instance
function M.execute_move(number, from_id, to_id, to_name, board)
  local stop = utils.spinner_start("Moving #" .. number .. " to " .. to_name .. "...")
  api.move_card(number, from_id, to_id, to_name, function(ok, err)
    if not ok then
      stop("Failed to move #" .. number .. ": " .. (err or "unknown error"))
      return
    end

    utils.spinner_update("Refreshing board...")

    -- Refresh the board
    api.fetch_all_columns(function(data)
      stop("Moved #" .. number .. " to " .. to_name)
      if data then
        board:refresh(data)
      end
    end)
  end)
end

return M

local api = require("okuban.api")
local picker = require("okuban.ui.picker")
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

  picker.select(targets, {
    prompt = "Move #" .. issue.number .. " to",
    format_item = function(item)
      return item.name
    end,
  }, function(target)
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

    -- Optimistic update: move the issue between columns in board data
    if board:is_open() and board.data and board.data.columns then
      local moved_issue = nil
      -- Remove from source column
      for _, col in ipairs(board.data.columns) do
        if col.label == from_id then
          for idx, iss in ipairs(col.issues) do
            if iss.number == number then
              moved_issue = table.remove(col.issues, idx)
              break
            end
          end
          break
        end
      end
      -- Insert into target column
      if moved_issue then
        for _, col in ipairs(board.data.columns) do
          if col.label == to_id then
            table.insert(col.issues, 1, moved_issue)
            break
          end
        end
      end
      board:refresh(board.data)
      stop("Moved #" .. number .. " to " .. to_name)
    end

    -- Delayed background sync (GitHub index lag)
    vim.defer_fn(function()
      api.fetch_all_columns(function(data)
        if data and board:is_open() then
          board:refresh(data)
        end
      end)
    end, 5000)
  end)
end

return M

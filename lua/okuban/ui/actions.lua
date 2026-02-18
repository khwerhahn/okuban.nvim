local api = require("okuban.api")
local config = require("okuban.config")
local picker = require("okuban.ui.picker")
local utils = require("okuban.utils")

local M = {}

local actions_win = nil
local actions_buf = nil

--- Close the actions menu.
function M.close()
  if actions_win and vim.api.nvim_win_is_valid(actions_win) then
    vim.api.nvim_win_close(actions_win, true)
  end
  actions_win = nil
  actions_buf = nil
end

--- Build the list of action items for an issue.
---@param issue table
---@param board table Board instance
---@return table[] actions Array of { key, label, callback }
--- @private Exposed for testing only.
function M._build_actions(issue, board)
  local actions = {}

  -- Move to column (always available — this is the triage mechanism)
  table.insert(actions, {
    key = "m",
    label = "Move to column...",
    callback = function()
      M.close()
      local move = require("okuban.ui.move")
      move.prompt_move(board)
    end,
  })

  -- View in browser
  table.insert(actions, {
    key = "v",
    label = "View in browser",
    callback = function()
      M.close()
      api.view_issue_in_browser(issue.number)
      utils.notify("Opening #" .. issue.number .. " in browser")
    end,
  })

  local is_open = issue.state ~= "CLOSED"

  -- Close issue (only for open issues)
  if is_open then
    table.insert(actions, {
      key = "c",
      label = "Close issue",
      callback = function()
        M.close()
        picker.confirm("Close issue #" .. issue.number .. "?", function(confirmed)
          if not confirmed then
            return
          end
          local stop = utils.spinner_start("Closing #" .. issue.number .. "...")
          api.close_issue(issue.number, function(ok, err)
            if not ok then
              stop("Failed to close #" .. issue.number .. ": " .. (err or ""))
              return
            end

            -- Optimistic update: remove the issue from board data immediately
            if board:is_open() and board.data and board.data.columns then
              for _, col in ipairs(board.data.columns) do
                for idx, iss in ipairs(col.issues) do
                  if iss.number == issue.number then
                    table.remove(col.issues, idx)
                    break
                  end
                end
              end
              board:refresh(board.data)
              stop("Closed #" .. issue.number)
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
        end)
      end,
    })
  end

  -- Assign to me (only for open issues)
  if is_open then
    table.insert(actions, {
      key = "a",
      label = "Assign to me",
      callback = function()
        M.close()
        local stop = utils.spinner_start("Assigning #" .. issue.number .. "...")
        api.assign_issue(issue.number, function(ok, err)
          if ok then
            utils.spinner_update("Refreshing board...")
            api.fetch_all_columns(function(data)
              stop("Assigned #" .. issue.number .. " to you")
              if data then
                board:refresh(data)
              end
            end)
          else
            stop("Failed to assign #" .. issue.number .. ": " .. (err or ""))
          end
        end)
      end,
    })
  end

  -- Code with Claude (only for open issues, when enabled and available)
  if is_open then
    local claude_cfg = config.get().claude
    if claude_cfg.enabled then
      local claude_mod = require("okuban.claude")
      if claude_mod.is_available() then
        local session = claude_mod.get_session(issue.number)

        if session and session.status == "running" then
          -- Running: show status info, no action
          table.insert(actions, {
            key = "x",
            label = "Claude is running...",
            callback = function()
              M.close()
              utils.notify("Claude is working on #" .. issue.number)
            end,
          })
        elseif session and session.session_id and (session.status == "completed" or session.status == "failed") then
          -- Completed/Failed with session_id: offer resume
          table.insert(actions, {
            key = "x",
            label = "Resume Claude session",
            callback = function()
              M.close()
              claude_mod.resume(issue, function(ok, err)
                if not ok then
                  utils.notify("Resume failed: " .. (err or "unknown"), vim.log.levels.ERROR)
                end
              end)
            end,
          })
        else
          -- No session: offer launch
          table.insert(actions, {
            key = "x",
            label = "Code with Claude",
            callback = function()
              M.close()
              claude_mod.launch(issue, function(ok, err)
                if not ok then
                  utils.notify("Failed: " .. (err or "unknown"), vim.log.levels.ERROR)
                end
              end)
            end,
          })
        end
      end
    end
  end

  return actions
end

--- Execute a specific action by key for the given issue.
--- Used by navigation keymaps in issue mode (replaces popup interaction).
---@param key string Action key (m, v, c, a, x)
---@param issue table Issue data
---@param board table Board instance
---@return boolean executed True if action was found and executed
function M.execute_action(key, issue, board)
  local action_list = M._build_actions(issue, board)
  for _, action in ipairs(action_list) do
    if action.key == key then
      action.callback()
      return true
    end
  end
  return false
end

--- Open the action menu for the currently selected card.
---@param board table Board instance
function M.open(board)
  -- Close existing menu if open
  if actions_win and vim.api.nvim_win_is_valid(actions_win) then
    M.close()
    return
  end

  local nav = board.navigation
  if not nav then
    return
  end

  local issue = nav:get_selected_issue()
  if not issue then
    utils.notify("No issue selected", vim.log.levels.WARN)
    return
  end

  local actions = M._build_actions(issue, board)

  -- Build display lines
  local title_text = "#" .. issue.number .. ": " .. (issue.title or "Untitled")
  local menu_width = math.max(36, #title_text + 4)
  if menu_width > 60 then
    menu_width = 60
    title_text = title_text:sub(1, 56) .. "..."
  end

  local lines = { "" }
  for _, action in ipairs(actions) do
    table.insert(lines, "  [" .. action.key .. "] " .. action.label)
  end
  table.insert(lines, "")

  -- Create buffer
  actions_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(actions_buf, 0, -1, false, lines)
  vim.bo[actions_buf].buftype = "nofile"
  vim.bo[actions_buf].bufhidden = "wipe"
  vim.bo[actions_buf].modifiable = false
  vim.bo[actions_buf].filetype = "okuban"

  -- Position: centered on screen
  local screen_w = vim.o.columns
  local screen_h = vim.o.lines
  local height = #lines

  actions_win = vim.api.nvim_open_win(actions_buf, true, {
    relative = "editor",
    row = math.floor((screen_h - height) / 2),
    col = math.floor((screen_w - menu_width) / 2),
    width = menu_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. title_text .. " ",
    title_pos = "center",
    zindex = 70,
  })

  vim.wo[actions_win].cursorline = false
  vim.wo[actions_win].wrap = false

  -- Set up keymaps for each action
  local opts = { buffer = actions_buf, nowait = true, silent = true }
  for _, action in ipairs(actions) do
    vim.keymap.set("n", action.key, action.callback, opts)
  end

  -- Close keymaps
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)
end

return M

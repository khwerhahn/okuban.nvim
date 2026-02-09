local api = require("okuban.api")
local config = require("okuban.config")
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
        vim.schedule(function()
          local confirm = vim.fn.confirm("Close issue #" .. issue.number .. "?", "&Yes\n&No", 2)
          if confirm ~= 1 then
            return
          end
          local stop = utils.spinner_start("Closing #" .. issue.number .. "...")
          api.close_issue(issue.number, function(ok, err)
            if ok then
              utils.spinner_update("Refreshing board...")
              api.fetch_all_columns(function(data)
                stop("Closed #" .. issue.number)
                if data then
                  board:refresh(data)
                end
              end)
            else
              stop("Failed to close #" .. issue.number .. ": " .. (err or ""))
            end
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
        table.insert(actions, {
          key = "x",
          label = "Code with Claude",
          callback = function()
            M.close()
            local session = claude_mod.get_session(issue.number)
            if session and session.status == "running" then
              utils.notify("Claude is already working on #" .. issue.number)
              return
            end
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

  return actions
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

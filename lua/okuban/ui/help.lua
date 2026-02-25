local config = require("okuban.config")

local M = {}

local help_win = nil
local help_buf = nil

--- Open a floating help window showing all keybindings.
function M.open()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    M.close()
    return
  end

  local km = config.get().keymaps
  local lines = {
    "  Navigation",
    "  ──────────",
    "  " .. km.column_left .. " / \xe2\x86\x90    Previous column",
    "  " .. km.column_right .. " / \xe2\x86\x92    Next column",
    "  " .. km.card_up .. " / \xe2\x86\x91    Previous card",
    "  " .. km.card_down .. " / \xe2\x86\x93    Next card",
    "",
    "  Actions",
    "  ───────",
    "  Enter    Expand / action menu",
    "  " .. km.move_card .. "        Move card to column",
    "  " .. km.new_issue .. "        New issue",
    "  " .. km.goto_current .. "        Go to current issue",
    "  " .. km.refresh .. "        Refresh board",
    "  " .. km.help .. "        Toggle this help",
    "  " .. km.close .. "        Close board",
    "",
    "  Commands",
    "  ────────",
    "  " .. km.setup_labels .. "        Setup labels",
    "  " .. km.switch_source .. "        Switch source",
    "  " .. km.triage .. "        Triage issues",
  }

  local width = 32
  local height = #lines

  help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].buftype = "nofile"
  vim.bo[help_buf].bufhidden = "wipe"
  vim.bo[help_buf].filetype = "okuban"
  vim.bo[help_buf].modifiable = false

  local screen_w = vim.o.columns
  local screen_h = vim.o.lines

  help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = "editor",
    row = math.floor((screen_h - height) / 2),
    col = math.floor((screen_w - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Help ",
    title_pos = "center",
    zindex = 60,
  })

  -- Close on q or Esc or ?
  local close_keys = { "q", "<Esc>", km.help }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, function()
      M.close()
    end, { buffer = help_buf, nowait = true, silent = true })
  end
end

--- Close the help window.
function M.close()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    vim.api.nvim_win_close(help_win, true)
  end
  help_win = nil
  help_buf = nil
end

return M

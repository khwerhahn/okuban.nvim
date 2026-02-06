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

  local keymaps = config.get().keymaps
  local lines = {
    "  Okuban Keybindings",
    "  ──────────────────",
    "",
    "  " .. keymaps.column_left .. "      Previous column",
    "  " .. keymaps.column_right .. "      Next column",
    "  " .. keymaps.card_up .. "      Previous card",
    "  " .. keymaps.card_down .. "      Next card",
    "  " .. keymaps.move_card .. "      Move card to column",
    "  " .. keymaps.refresh .. "      Refresh board",
    "  " .. keymaps.help .. "      Toggle this help",
    "  " .. keymaps.close .. "      Close board",
  }

  local width = 30
  local height = #lines

  help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].buftype = "nofile"
  vim.bo[help_buf].bufhidden = "wipe"
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
  local close_keys = { "q", "<Esc>", keymaps.help }
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

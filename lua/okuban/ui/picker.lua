--- Shared floating picker/input/confirm dialogs for okuban.
--- All dialogs open centered on screen with a semi-transparent backdrop.
local M = {}

-- ---------------------------------------------------------------------------
-- Backdrop overlay
-- ---------------------------------------------------------------------------

local backdrop_win = nil
local backdrop_buf = nil

--- Show a full-screen semi-transparent backdrop behind modals.
function M.show_backdrop()
  if backdrop_win and vim.api.nvim_win_is_valid(backdrop_win) then
    return
  end
  backdrop_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[backdrop_buf].buftype = "nofile"
  vim.bo[backdrop_buf].bufhidden = "wipe"
  backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines,
    style = "minimal",
    focusable = false,
    zindex = 65,
  })
  vim.wo[backdrop_win].winhighlight = "Normal:OkubanBackdrop"
end

--- Close the backdrop overlay.
function M.close_backdrop()
  if backdrop_win and vim.api.nvim_win_is_valid(backdrop_win) then
    vim.api.nvim_win_close(backdrop_win, true)
  end
  backdrop_win = nil
  backdrop_buf = nil
end

-- ---------------------------------------------------------------------------
-- Picker window (shared across select / input / confirm)
-- ---------------------------------------------------------------------------

local picker_win = nil
local picker_buf = nil

--- Close the floating picker if open (does NOT close backdrop).
function M.close_picker()
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_close(picker_win, true)
  end
  picker_win = nil
  picker_buf = nil
end

--- Close picker + backdrop.
function M.close()
  M.close_picker()
  M.close_backdrop()
end

-- ---------------------------------------------------------------------------
-- select — centered floating list picker
-- ---------------------------------------------------------------------------

--- Open a centered floating list picker.
--- j/k to navigate, CR to select, Esc/q to cancel.
---@param items table[] Items to choose from
---@param opts { prompt: string, format_item: fun(item: table): string }
---@param on_choice fun(item: table|nil)
function M.select(items, opts, on_choice)
  M.close_picker()

  if not items or #items == 0 then
    on_choice(nil)
    return
  end

  M.show_backdrop()

  local format = opts.format_item or tostring
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, "    " .. format(item))
  end

  local prompt = opts.prompt or "Select:"
  local footer_len = 42
  local width = math.max(#prompt + 4, footer_len)
  for _, line in ipairs(lines) do
    if #line + 4 > width then
      width = #line + 4
    end
  end
  if width > 80 then
    width = 80
  end
  if width < 40 then
    width = 40
  end

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].buftype = "nofile"
  vim.bo[picker_buf].bufhidden = "wipe"
  vim.bo[picker_buf].modifiable = false
  vim.bo[picker_buf].filetype = "okuban"

  local sw = vim.o.columns
  local sh = vim.o.lines
  local height = #lines
  if height > 20 then
    height = 20
  end

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    row = math.floor((sh - height) / 2),
    col = math.floor((sw - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " ",
    title_pos = "center",
    footer = " j/k Navigate  Enter Select  Esc Cancel",
    footer_pos = "center",
    zindex = 70,
  })

  vim.wo[picker_win].cursorline = true
  vim.wo[picker_win].wrap = false
  vim.wo[picker_win].number = false
  vim.wo[picker_win].relativenumber = false
  vim.wo[picker_win].signcolumn = "no"

  vim.api.nvim_win_set_cursor(picker_win, { 1, 0 })

  local called = false
  local function select_current()
    if called then
      return
    end
    called = true
    local row = vim.api.nvim_win_get_cursor(picker_win)[1]
    M.close_picker()
    on_choice(items[row])
  end

  local function cancel()
    if called then
      return
    end
    called = true
    M.close()
    on_choice(nil)
  end

  local buf_opts = { buffer = picker_buf, nowait = true, silent = true }
  vim.keymap.set("n", "j", function()
    local row = vim.api.nvim_win_get_cursor(picker_win)[1]
    if row < #items then
      vim.api.nvim_win_set_cursor(picker_win, { row + 1, 0 })
    end
  end, buf_opts)
  vim.keymap.set("n", "k", function()
    local row = vim.api.nvim_win_get_cursor(picker_win)[1]
    if row > 1 then
      vim.api.nvim_win_set_cursor(picker_win, { row - 1, 0 })
    end
  end, buf_opts)
  vim.keymap.set("n", "<CR>", select_current, buf_opts)
  vim.keymap.set("n", "<Esc>", cancel, buf_opts)
  vim.keymap.set("n", "q", cancel, buf_opts)
end

-- ---------------------------------------------------------------------------
-- input — centered floating single-line input
-- ---------------------------------------------------------------------------

--- Open a centered floating input prompt.
--- Type text, CR to confirm, Esc to cancel.
---@param opts { prompt: string }
---@param on_confirm fun(text: string|nil)
function M.input(opts, on_confirm)
  M.close_picker()
  M.show_backdrop()

  local prompt = opts.prompt or "Input:"
  local width = math.max(60, #prompt + 10)
  if width > 80 then
    width = 80
  end

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype = "nofile"
  vim.bo[picker_buf].bufhidden = "wipe"
  vim.bo[picker_buf].swapfile = false
  vim.bo[picker_buf].filetype = "okuban"

  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, { "" })

  local sw = vim.o.columns
  local sh = vim.o.lines

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    row = math.floor(sh / 2),
    col = math.floor((sw - width) / 2),
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " ",
    title_pos = "center",
    footer = " Enter Confirm  Esc Cancel",
    footer_pos = "center",
    zindex = 70,
  })

  vim.wo[picker_win].wrap = false
  vim.wo[picker_win].number = false
  vim.wo[picker_win].relativenumber = false
  vim.wo[picker_win].signcolumn = "no"

  vim.cmd("startinsert")

  local called = false
  local function confirm()
    if called then
      return
    end
    called = true
    local line = vim.api.nvim_buf_get_lines(picker_buf, 0, 1, false)[1] or ""
    M.close_picker()
    on_confirm(line)
  end

  local function cancel()
    if called then
      return
    end
    called = true
    M.close()
    on_confirm(nil)
  end

  local buf_opts = { buffer = picker_buf, nowait = true, silent = true }
  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    confirm()
  end, buf_opts)
  vim.keymap.set("n", "<CR>", confirm, buf_opts)
  vim.keymap.set("n", "<Esc>", cancel, buf_opts)
end

-- ---------------------------------------------------------------------------
-- confirm — centered floating yes/no dialog
-- ---------------------------------------------------------------------------

--- Open a centered floating yes/no confirmation dialog.
--- y/Enter to confirm, n/Esc/q to cancel.
---@param prompt string Question to display
---@param callback fun(confirmed: boolean)
function M.confirm(prompt, callback)
  M.close_picker()
  M.show_backdrop()

  local lines = {
    "    " .. prompt,
    "",
    "    [y] Yes    [n] No",
  }

  local width = math.max(40, #lines[1] + 6, #lines[3] + 6)
  if width > 80 then
    width = 80
  end

  picker_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].buftype = "nofile"
  vim.bo[picker_buf].bufhidden = "wipe"
  vim.bo[picker_buf].modifiable = false
  vim.bo[picker_buf].filetype = "okuban"

  local sw = vim.o.columns
  local sh = vim.o.lines

  picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    row = math.floor((sh - #lines) / 2),
    col = math.floor((sw - width) / 2),
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " Confirm ",
    title_pos = "center",
    zindex = 70,
  })

  vim.wo[picker_win].cursorline = false
  vim.wo[picker_win].wrap = false
  vim.wo[picker_win].number = false
  vim.wo[picker_win].relativenumber = false
  vim.wo[picker_win].signcolumn = "no"

  local called = false
  local function yes()
    if called then
      return
    end
    called = true
    M.close()
    callback(true)
  end

  local function no()
    if called then
      return
    end
    called = true
    M.close()
    callback(false)
  end

  local buf_opts = { buffer = picker_buf, nowait = true, silent = true }
  vim.keymap.set("n", "y", yes, buf_opts)
  vim.keymap.set("n", "<CR>", yes, buf_opts)
  vim.keymap.set("n", "n", no, buf_opts)
  vim.keymap.set("n", "<Esc>", no, buf_opts)
  vim.keymap.set("n", "q", no, buf_opts)
end

return M

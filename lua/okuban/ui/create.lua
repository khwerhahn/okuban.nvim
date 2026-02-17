local api = require("okuban.api")
local config = require("okuban.config")
local utils = require("okuban.utils")

local M = {}

local create_win = nil
local create_buf = nil
local template_cache = nil -- nil=not fetched, false=none, table=list

-- ---------------------------------------------------------------------------
-- Backdrop overlay (dims everything behind the picker / body editor)
-- ---------------------------------------------------------------------------

local backdrop_win = nil
local backdrop_buf = nil

--- Show a full-screen semi-transparent backdrop behind modals.
local function show_backdrop()
  if backdrop_win and vim.api.nvim_win_is_valid(backdrop_win) then
    return -- already visible
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
    zindex = 65, -- between board (50) and picker/editor (70)
  })
  vim.wo[backdrop_win].winhighlight = "Normal:OkubanBackdrop"
end

--- Close the backdrop overlay.
local function close_backdrop()
  if backdrop_win and vim.api.nvim_win_is_valid(backdrop_win) then
    vim.api.nvim_win_close(backdrop_win, true)
  end
  backdrop_win = nil
  backdrop_buf = nil
end

-- ---------------------------------------------------------------------------
-- Floating picker helpers (centered on screen, replaces vim.ui.select/input)
-- ---------------------------------------------------------------------------

local picker_win = nil
local picker_buf = nil

--- Close the floating picker if open.
local function close_picker()
  if picker_win and vim.api.nvim_win_is_valid(picker_win) then
    vim.api.nvim_win_close(picker_win, true)
  end
  picker_win = nil
  picker_buf = nil
end

--- Open a centered floating list picker.
--- j/k to navigate, CR to select, Esc/q to cancel.
---@param items table[] Items to choose from
---@param opts { prompt: string, format_item: fun(item: table): string }
---@param on_choice fun(item: table|nil)
function M._float_select(items, opts, on_choice)
  close_picker()

  if not items or #items == 0 then
    on_choice(nil)
    return
  end

  show_backdrop()

  local format = opts.format_item or tostring
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, "    " .. format(item))
  end

  local prompt = opts.prompt or "Select:"
  local footer_len = 42 -- " j/k Navigate  Enter Select  Esc Cancel"
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
    close_picker()
    on_choice(items[row])
  end

  local function cancel()
    if called then
      return
    end
    called = true
    close_picker()
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

--- Open a centered floating input prompt.
--- Type text, CR to confirm, Esc to cancel.
---@param opts { prompt: string }
---@param on_confirm fun(text: string|nil)
function M._float_input(opts, on_confirm)
  close_picker()
  show_backdrop()

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
    close_picker()
    on_confirm(line)
  end

  local function cancel()
    if called then
      return
    end
    called = true
    close_picker()
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
-- Public API
-- ---------------------------------------------------------------------------

--- Close the create window and all overlays.
function M.close()
  close_picker()
  close_backdrop()
  if create_win and vim.api.nvim_win_is_valid(create_win) then
    vim.api.nvim_win_close(create_win, true)
  end
  create_win = nil
  create_buf = nil
end

--- Parse YAML frontmatter from a template file.
--- Returns the body (with frontmatter stripped) and any labels found.
---@param content string
---@return string body
---@return string[] labels
---@return string|nil name
function M._parse_frontmatter(content)
  if not content or content == "" then
    return "", {}, nil
  end

  -- Check for frontmatter delimiters
  local fm_start = content:match("^%-%-%-\n()")
  if not fm_start then
    return content, {}, nil
  end

  local fm_close = content:find("\n%-%-%-", fm_start)
  if not fm_close then
    return content, {}, nil
  end

  local frontmatter = content:sub(fm_start, fm_close - 1) .. "\n"
  local body = content:sub(fm_close + 4) -- skip "\n---"
  -- Strip leading newlines from body
  body = body:gsub("^\n+", "")

  local labels = {}
  local name = nil

  -- Extract name field
  local name_match = frontmatter:match("name:%s*(.-)%s*\n")
  if name_match and name_match ~= "" then
    -- Strip surrounding quotes
    name = name_match:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
  end

  -- Extract labels (YAML list format: "labels: [a, b]" or multiline "- a")
  local inline_labels = frontmatter:match("labels:%s*%[(.-)%]")
  if inline_labels then
    for label in inline_labels:gmatch("[^,]+") do
      label = vim.trim(label):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      if label ~= "" then
        table.insert(labels, label)
      end
    end
  else
    -- Multiline YAML list
    local in_labels = false
    for line in frontmatter:gmatch("[^\n]+") do
      if line:match("^labels:%s*$") then
        in_labels = true
      elseif in_labels then
        local item = line:match("^%s*%-%s*(.+)")
        if item then
          item = vim.trim(item):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
          if item ~= "" then
            table.insert(labels, item)
          end
        else
          in_labels = false
        end
      end
    end
  end

  return body, labels, name
end

--- Fetch issue templates from the repo (cached per session).
---@param callback fun(templates: table[]|false)
function M._fetch_templates(callback)
  if template_cache ~= nil then
    callback(template_cache)
    return
  end

  api.detect_repo_info(function(owner, name)
    if not owner or not name then
      template_cache = false
      callback(false)
      return
    end

    local gh_cmd = api._gh_base_cmd()
    local cmd = vim.list_extend(vim.deepcopy(gh_cmd), {
      "api",
      "repos/" .. owner .. "/" .. name .. "/contents/.github/ISSUE_TEMPLATE",
      "--jq",
      '[.[] | select(.name | test("\\\\.md$")) | {name: .name, path: .path, download_url: .download_url}]',
    })

    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          template_cache = false
          callback(false)
          return
        end
        local ok, data = pcall(vim.json.decode, result.stdout)
        if not ok or type(data) ~= "table" or #data == 0 then
          template_cache = false
          callback(false)
          return
        end
        template_cache = data
        callback(data)
      end)
    end)
  end)
end

--- Fetch the content of a single template file.
---@param template table { name, path, download_url }
---@param callback fun(content: string|nil)
function M._fetch_template_content(template, callback)
  if template._content then
    callback(template._content)
    return
  end

  local gh_cmd = api._gh_base_cmd()
  api.detect_repo_info(function(owner, name)
    if not owner or not name then
      callback(nil)
      return
    end
    local cmd = vim.list_extend(vim.deepcopy(gh_cmd), {
      "api",
      "repos/" .. owner .. "/" .. name .. "/contents/" .. template.path,
      "--jq",
      ".content",
    })

    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 or not result.stdout then
          callback(nil)
          return
        end
        -- GitHub API returns base64-encoded content
        local b64 = vim.trim(result.stdout)
        local ok, decoded = pcall(vim.base64.decode, b64)
        if not ok or not decoded then
          callback(nil)
          return
        end
        template._content = decoded
        callback(decoded)
      end)
    end)
  end)
end

--- Open the body editor floating buffer.
---@param title string Issue title
---@param body_text string Pre-filled body from template
---@param extra_labels string[] Labels from template frontmatter
---@param column table Selected kanban column { label, name }
---@param board table Board instance
function M._open_body_buffer(title, body_text, extra_labels, column, board)
  -- Close any existing create window (keeps backdrop)
  close_picker()
  if create_win and vim.api.nvim_win_is_valid(create_win) then
    vim.api.nvim_win_close(create_win, true)
  end
  create_win = nil
  create_buf = nil
  show_backdrop()

  local sw = vim.o.columns
  local sh = vim.o.lines
  local width = math.floor(sw * 0.7)
  local height = math.floor(sh * 0.5)
  if width < 40 then
    width = 40
  end
  if height < 10 then
    height = 10
  end

  create_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[create_buf].buftype = "nofile"
  vim.bo[create_buf].bufhidden = "wipe"
  vim.bo[create_buf].swapfile = false
  vim.bo[create_buf].filetype = "okuban"

  -- Pre-fill with template body
  local lines = vim.split(body_text or "", "\n")
  vim.api.nvim_buf_set_lines(create_buf, 0, -1, false, lines)

  -- Enable markdown syntax highlighting
  vim.bo[create_buf].syntax = "markdown"

  local title_display = title
  if #title_display > 50 then
    title_display = title_display:sub(1, 47) .. "..."
  end

  create_win = vim.api.nvim_open_win(create_buf, true, {
    relative = "editor",
    row = math.floor((sh - height) / 2),
    col = math.floor((sw - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " New: " .. title_display .. " ",
    title_pos = "center",
    footer = " Ctrl+Enter Submit  Esc Cancel",
    footer_pos = "center",
    zindex = 70,
  })

  vim.wo[create_win].wrap = true
  vim.wo[create_win].number = false
  vim.wo[create_win].relativenumber = false
  vim.wo[create_win].signcolumn = "no"

  -- Start in insert mode at end
  vim.cmd("startinsert")

  -- Submit keymap: Ctrl-Enter (normal + insert)
  local submit = function()
    M._submit(title, board, column, extra_labels)
  end
  local buf_opts = { buffer = create_buf, nowait = true, silent = true }
  vim.keymap.set("n", "<C-CR>", submit, buf_opts)
  vim.keymap.set("i", "<C-CR>", function()
    vim.cmd("stopinsert")
    submit()
  end, buf_opts)

  -- Cancel keymap: Esc in normal mode
  vim.keymap.set("n", "<Esc>", function()
    M._cancel(board)
  end, buf_opts)
end

--- Submit the new issue.
---@param title string
---@param board table Board instance
---@param column table Selected column { label, name }
---@param extra_labels string[] Additional labels from template
function M._submit(title, board, column, extra_labels)
  if not create_buf or not vim.api.nvim_buf_is_valid(create_buf) then
    return
  end

  local body_lines = vim.api.nvim_buf_get_lines(create_buf, 0, -1, false)
  local body = table.concat(body_lines, "\n")

  M.close()

  -- Build labels list
  local labels = {}
  -- Add kanban column label (label mode only)
  if config.get().source == "labels" and column and column.label then
    table.insert(labels, column.label)
  end
  -- Add template labels
  if extra_labels then
    for _, lbl in ipairs(extra_labels) do
      table.insert(labels, lbl)
    end
  end

  local stop = utils.spinner_start("Creating issue...")
  api.create_issue(title, body, labels, function(ok, number, err, url)
    if not ok then
      stop("Failed: " .. (err or "unknown error"))
      return
    end

    local function refresh_board()
      utils.spinner_update("Refreshing board...")
      api.fetch_all_columns(function(data)
        stop("Created #" .. (number or "?"))
        if data and board:is_open() then
          board:refresh(data)
        end
      end)
    end

    -- In project mode: add issue to project and set status column
    if config.get().source == "project" and url and column and column.option_id then
      local api_project = require("okuban.api_project")
      local project_id = api_project.get_cached_project_id()
      local status_field = api_project.get_cached_status_field()
      local cfg = config.get()
      local proj_number = cfg.project.number
      local proj_owner = cfg.project.owner

      if project_id and status_field and proj_number and proj_owner then
        utils.spinner_update("Adding to project...")
        api_project.add_item(url, proj_number, proj_owner, function(item_id, add_err)
          if not item_id then
            stop("Created #" .. (number or "?") .. " but failed to add to project: " .. (add_err or ""))
            return
          end
          utils.spinner_update("Setting status...")
          api_project.move_item(item_id, project_id, status_field.id, column.option_id, function(move_ok, move_err)
            if not move_ok then
              stop("Created #" .. (number or "?") .. " but failed to set status: " .. (move_err or ""))
              return
            end
            refresh_board()
          end)
        end)
        return
      end
    end

    refresh_board()
  end)
end

--- Cancel the create flow.
---@param board table Board instance
function M._cancel(board)
  if create_buf and vim.api.nvim_buf_is_valid(create_buf) then
    local lines = vim.api.nvim_buf_get_lines(create_buf, 0, -1, false)
    local has_content = false
    for _, line in ipairs(lines) do
      if vim.trim(line) ~= "" then
        has_content = true
        break
      end
    end

    if has_content then
      local confirm = vim.fn.confirm("Discard draft issue?", "&Yes\n&No", 2)
      if confirm ~= 1 then
        return
      end
    end
  end

  M.close()

  -- Restore focus to board
  if board and board.windows and board.navigation then
    local win = board.windows[board.navigation.column_index]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
end

--- Entry point: open the new issue creation flow.
--- All steps use centered floating pickers overlaid on the board.
---@param board table Board instance
function M.open(board)
  if not board or not board:is_open() then
    return
  end

  -- Step 1: Fetch templates
  M._fetch_templates(function(templates)
    -- Step 2: Template picker (skip if no templates)
    local function with_template(template_body, template_labels)
      -- Step 3: Column picker (use project status options or label config)
      local cfg = config.get()
      local col_choices = {}
      if cfg.source == "project" then
        local api_project = require("okuban.api_project")
        local status_field = api_project.get_cached_status_field()
        if status_field and status_field.options then
          for _, opt in ipairs(status_field.options) do
            table.insert(col_choices, { label = opt.id, name = opt.name, option_id = opt.id })
          end
        end
      end
      if #col_choices == 0 then
        for _, col in ipairs(cfg.columns) do
          table.insert(col_choices, { label = col.label, name = col.name })
        end
      end

      M._float_select(col_choices, {
        prompt = "Select column",
        format_item = function(item)
          return item.name
        end,
      }, function(column)
        if not column then
          close_backdrop()
          return
        end

        -- Step 4: Title input
        M._float_input({ prompt = "Issue title" }, function(title)
          if not title or vim.trim(title) == "" then
            if title ~= nil then -- nil = cancelled, "" = empty
              utils.notify("Title cannot be empty", vim.log.levels.WARN)
            end
            close_backdrop()
            return
          end

          -- Step 5: Body editor
          M._open_body_buffer(title, template_body or "", template_labels or {}, column, board)
        end)
      end)
    end

    if templates and #templates > 0 then
      -- Add "Blank" option
      local choices = { { name = "(Blank)", path = nil } }
      for _, t in ipairs(templates) do
        local display = t.name:gsub("%.md$", ""):gsub("[_-]", " ")
        table.insert(choices, { name = display, path = t.path, _template = t })
      end

      M._float_select(choices, {
        prompt = "Issue template",
        format_item = function(item)
          return item.name
        end,
      }, function(choice)
        if not choice then
          close_backdrop()
          return
        end
        if not choice._template then
          -- Blank template
          with_template("", {})
          return
        end

        -- Fetch template content
        M._fetch_template_content(choice._template, function(content)
          if content then
            local body, labels = M._parse_frontmatter(content)
            with_template(body, labels)
          else
            with_template("", {})
          end
        end)
      end)
    else
      with_template("", {})
    end
  end)
end

--- Reset template cache (for testing).
function M._reset_cache()
  template_cache = nil
end

return M

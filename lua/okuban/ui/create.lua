local api = require("okuban.api")
local config = require("okuban.config")
local picker = require("okuban.ui.picker")
local utils = require("okuban.utils")

local M = {}

local create_win = nil
local create_buf = nil
local template_cache = nil -- nil=not fetched, false=none, table=list

-- Expose picker methods for test backward compatibility
M._float_select = picker.select
M._float_input = picker.input

--- Close the create window and all overlays.
function M.close()
  picker.close()
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
  picker.close_picker()
  if create_win and vim.api.nvim_win_is_valid(create_win) then
    vim.api.nvim_win_close(create_win, true)
  end
  create_win = nil
  create_buf = nil
  picker.show_backdrop()

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
    footer = " Ctrl+s Submit  Esc Cancel",
    footer_pos = "center",
    zindex = 70,
  })

  vim.wo[create_win].wrap = true
  vim.wo[create_win].number = false
  vim.wo[create_win].relativenumber = false
  vim.wo[create_win].signcolumn = "no"

  -- Start in insert mode at end
  vim.cmd("startinsert")

  -- Submit keymap: Ctrl-s (normal + insert)
  local submit = function()
    M._submit(title, board, column, extra_labels)
  end
  local buf_opts = { buffer = create_buf, nowait = true, silent = true }
  vim.keymap.set("n", "<C-s>", submit, buf_opts)
  vim.keymap.set("i", "<C-s>", function()
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

    -- Optimistic update: inject the new issue into board data immediately
    if number and board:is_open() and board.data and board.data.columns then
      local optimistic_issue = {
        number = number,
        title = title,
        body = body,
        assignees = {},
        labels = labels and vim.tbl_map(function(l)
          return { name = l }
        end, labels) or {},
        state = "OPEN",
      }
      -- Find the target column and prepend the issue
      for _, col in ipairs(board.data.columns) do
        if col.label == column.label then
          table.insert(col.issues, 1, optimistic_issue)
          break
        end
      end
      board:refresh(board.data)
      stop("Created #" .. number)
    end

    -- Background sync: fetch real data to replace the optimistic entry.
    -- Delayed to give GitHub's search index time to include the new issue.
    -- Without delay, gh issue list returns stale results and the optimistic
    -- entry vanishes until the next poll cycle.
    local function background_sync()
      local delay = 5000 -- 5 seconds
      vim.defer_fn(function()
        api.fetch_all_columns(function(data)
          if data and board:is_open() then
            board:refresh(data)
          end
        end)
      end, delay)
    end

    -- In project mode: add issue to project and set status column, then sync
    if config.get().source == "project" and url and column and column.option_id then
      local api_project = require("okuban.api_project")
      local project_id = api_project.get_cached_project_id()
      local status_field = api_project.get_cached_status_field()
      local cfg = config.get()
      local proj_number = cfg.project.number
      local proj_owner = cfg.project.owner

      if project_id and status_field and proj_number and proj_owner then
        api_project.add_item(url, proj_number, proj_owner, function(item_id, add_err)
          if not item_id then
            utils.notify("Failed to add to project: " .. (add_err or ""), vim.log.levels.WARN)
            background_sync()
            return
          end
          api_project.move_item(item_id, project_id, status_field.id, column.option_id, function(move_ok, move_err)
            if not move_ok then
              utils.notify("Failed to set status: " .. (move_err or ""), vim.log.levels.WARN)
            end
            background_sync()
          end)
        end)
        return
      end
    end

    background_sync()
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
      -- Close the body editor first so confirm dialog shows on top
      if create_win and vim.api.nvim_win_is_valid(create_win) then
        vim.api.nvim_win_close(create_win, true)
      end
      create_win = nil
      create_buf = nil

      picker.confirm("Discard draft issue?", function(confirmed)
        if not confirmed then
          return
        end
        picker.close()
        -- Restore focus to board
        if board and board.windows and board.navigation then
          local win = board.windows[board.navigation.column_index]
          if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_current_win(win)
          end
        end
      end)
      return
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
          picker.close_backdrop()
          return
        end

        -- Step 4: Title input
        M._float_input({ prompt = "Issue title" }, function(title)
          if not title or vim.trim(title) == "" then
            if title ~= nil then -- nil = cancelled, "" = empty
              utils.notify("Title cannot be empty", vim.log.levels.WARN)
            end
            picker.close_backdrop()
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
          picker.close_backdrop()
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

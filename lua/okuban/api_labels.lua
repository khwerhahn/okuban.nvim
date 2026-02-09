local utils = require("okuban.utils")

local M = {}

--- Session-level board data cache (survives board close/reopen).
local board_cache = nil ---@type table|nil
local board_cache_ts = 0 ---@type integer

--- Get the gh base command from the shared api module.
---@return string[]
local function gh_base_cmd()
  return require("okuban.api")._gh_base_cmd()
end

-- ---------------------------------------------------------------------------
-- Label editing
-- ---------------------------------------------------------------------------

--- Edit labels on an issue (remove one, add another).
---@param number integer Issue number
---@param remove_label string Label to remove
---@param add_label string Label to add
---@param callback fun(ok: boolean, err: string|nil)
function M.edit_labels(number, remove_label, add_label, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "edit",
    tostring(number),
    "--remove-label",
    remove_label,
    "--add-label",
    add_label,
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, result.stderr or "Failed to edit labels")
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Fetch issues
-- ---------------------------------------------------------------------------

local ISSUE_FIELDS = "number,title,body,assignees,labels,state"

--- Fetch issues for a single label.
---@param label string The label to filter by
---@param state string|nil Issue state filter: "open", "closed", or "all" (default: "open")
---@param limit integer|nil Max issues to fetch (default: 100)
---@param callback fun(issues: table[]|nil, err: string|nil)
function M.fetch_column(label, state, limit, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "list",
    "--label",
    label,
    "--json",
    ISSUE_FIELDS,
    "--limit",
    tostring(limit or 100),
    "--state",
    state or "open",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to fetch issues for " .. label .. ": " .. (result.stderr or ""))
        return
      end
      local ok, issues = pcall(vim.json.decode, result.stdout)
      if not ok or type(issues) ~= "table" then
        callback({}, nil)
        return
      end
      callback(issues, nil)
    end)
  end)
end

--- Fetch unsorted issues (open issues without any okuban: label).
---@param columns table[] The configured columns
---@param callback fun(issues: table[]|nil, err: string|nil)
function M.fetch_unsorted(columns, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "list",
    "--json",
    ISSUE_FIELDS,
    "--limit",
    "100",
    "--state",
    "open",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to fetch issues: " .. (result.stderr or ""))
        return
      end
      local ok, all_issues = pcall(vim.json.decode, result.stdout)
      if not ok or type(all_issues) ~= "table" then
        callback({}, nil)
        return
      end

      -- Build a set of kanban labels for fast lookup
      local kanban_labels = {}
      for _, col in ipairs(columns) do
        kanban_labels[col.label] = true
      end

      -- Filter: only keep issues that have NO okuban: label
      local unsorted = {}
      for _, issue in ipairs(all_issues) do
        local has_kanban = false
        if issue.labels then
          for _, lbl in ipairs(issue.labels) do
            if kanban_labels[lbl.name] then
              has_kanban = true
              break
            end
          end
        end
        if not has_kanban then
          table.insert(unsorted, issue)
        end
      end

      callback(unsorted, nil)
    end)
  end)
end

--- Fetch all columns in parallel and return structured board data.
---@param callback fun(data: table|nil)
function M.fetch_all_columns(callback)
  local cfg = require("okuban.config").get()
  local columns = cfg.columns
  local total = #columns + (cfg.show_unsorted and 1 or 0)
  local pending = total
  local results = {}

  local function on_done()
    pending = pending - 1
    if pending == 0 then
      -- Build ordered result
      local board_data = { columns = {} }
      for _, col in ipairs(columns) do
        table.insert(board_data.columns, {
          label = col.label,
          name = col.name,
          color = col.color,
          issues = results[col.label] or {},
          limit = col.limit,
        })
      end
      if cfg.show_unsorted then
        board_data.unsorted = results["_unsorted"] or {}
      end
      board_cache = board_data
      board_cache_ts = os.time()
      callback(board_data)
    end
  end

  -- Fire all column fetches in parallel
  for _, col in ipairs(columns) do
    M.fetch_column(col.label, col.state, col.limit, function(issues, err)
      if err then
        utils.notify(err, vim.log.levels.WARN)
      end
      results[col.label] = issues or {}
      on_done()
    end)
  end

  -- Fetch unsorted if enabled
  if cfg.show_unsorted then
    M.fetch_unsorted(columns, function(issues, err)
      if err then
        utils.notify(err, vim.log.levels.WARN)
      end
      results["_unsorted"] = issues or {}
      on_done()
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Label management
-- ---------------------------------------------------------------------------

--- All labels that can be created by OkubanSetup.
local kanban_labels = {
  { name = "okuban:backlog", color = "c5def5", description = "Kanban: Not yet planned" },
  { name = "okuban:todo", color = "0075ca", description = "Kanban: Planned for work" },
  { name = "okuban:in-progress", color = "fbca04", description = "Kanban: Actively being worked on" },
  { name = "okuban:review", color = "d4c5f9", description = "Kanban: Awaiting review" },
  { name = "okuban:done", color = "0e8a16", description = "Kanban: Completed" },
}

local full_labels = {
  { name = "type: bug", color = "d73a4a", description = "Something is not working" },
  { name = "type: feature", color = "0075ca", description = "New functionality" },
  { name = "type: docs", color = "fef2c0", description = "Documentation improvement" },
  { name = "type: chore", color = "e6e6e6", description = "Maintenance, refactoring, CI" },
  { name = "priority: critical", color = "d73a4a", description = "Drop everything" },
  { name = "priority: high", color = "d93f0b", description = "Do this cycle" },
  { name = "priority: medium", color = "fbca04", description = "Important but not urgent" },
  { name = "priority: low", color = "0e8a16", description = "Backlog / nice-to-have" },
  { name = "good first issue", color = "7057ff", description = "Good for newcomers" },
  { name = "help wanted", color = "008672", description = "Maintainer seeks help" },
  { name = "needs: triage", color = "fbca04", description = "Needs initial assessment" },
  { name = "needs: repro", color = "fbca04", description = "Needs reproduction steps" },
}

--- Create a single label on the repo (idempotent via --force).
---@param label table { name, color, description }
---@param callback fun(ok: boolean)
function M.create_label(label, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "label",
    "create",
    label.name,
    "--color",
    label.color,
    "--description",
    label.description,
    "--force",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      callback(result.code == 0)
    end)
  end)
end

--- Create all labels for OkubanSetup.
---@param full boolean If true, create all labels including type/priority/community
---@param callback fun(created: integer, failed: integer)
function M.create_all_labels(full, callback)
  local labels = vim.deepcopy(kanban_labels)
  if full then
    vim.list_extend(labels, full_labels)
  end

  local pending = #labels
  local created = 0
  local failed = 0

  for _, label in ipairs(labels) do
    M.create_label(label, function(ok)
      if ok then
        created = created + 1
      else
        failed = failed + 1
      end
      pending = pending - 1
      if pending == 0 then
        callback(created, failed)
      end
    end)
  end
end

--- Return cached board data if it exists and is younger than max_age seconds.
---@param max_age integer Maximum cache age in seconds
---@return table|nil board_data
function M.get_cached_board_data(max_age)
  if board_cache and (os.time() - board_cache_ts) < max_age then
    return board_cache
  end
  return nil
end

return M

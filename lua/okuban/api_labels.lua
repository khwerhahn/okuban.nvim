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
  local effective_limits = {}

  local initial = cfg.initial_fetch_limit or 10

  local function on_done()
    pending = pending - 1
    if pending == 0 then
      -- Build ordered result
      local board_data = { columns = {} }
      for i, col in ipairs(columns) do
        local issues = results[col.label] or {}
        local eff = effective_limits[col.label]
        table.insert(board_data.columns, {
          label = col.label,
          name = col.name,
          color = col.color,
          issues = issues,
          limit = col.limit,
          has_more = eff and #issues >= eff or false,
          expanded = board_cache and board_cache.columns[i] and board_cache.columns[i].expanded or false,
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
  for i, col in ipairs(columns) do
    local full_limit = col.limit or 100
    -- Use initial limit unless this column was previously expanded
    local prev = board_cache and board_cache.columns[i]
    local effective = full_limit
    if initial > 0 and not (prev and prev.expanded) then
      effective = math.min(initial, full_limit)
    end
    effective_limits[col.label] = effective

    M.fetch_column(col.label, col.state, effective, function(issues, err)
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

--- Columns currently being expanded (concurrency guard).
local expanding_columns = {}

--- Expand a column by fetching more issues (re-fetch with full limit).
---@param col_index integer Column index in board_data.columns (1-based)
---@param callback fun(ok: boolean, err: string|nil)
function M.expand_column(col_index, callback)
  if not board_cache or not board_cache.columns[col_index] then
    callback(false, "Column not found")
    return
  end
  local col_data = board_cache.columns[col_index]
  if col_data.expanded then
    callback(true, nil)
    return
  end
  if expanding_columns[col_index] then
    callback(false, "Expansion already in progress")
    return
  end

  local cfg = require("okuban.config").get()
  local col_config = cfg.columns[col_index]
  if not col_config then
    callback(false, "Config not found")
    return
  end

  expanding_columns[col_index] = true
  local full_limit = col_config.limit or 100
  M.fetch_column(col_config.label, col_config.state, full_limit, function(issues, err)
    expanding_columns[col_index] = nil
    if err then
      callback(false, err)
      return
    end
    col_data.issues = issues or {}
    col_data.has_more = #col_data.issues >= full_limit
    col_data.expanded = true
    board_cache_ts = os.time()
    callback(true, nil)
  end)
end

-- ---------------------------------------------------------------------------
-- Sub-issue counts
-- ---------------------------------------------------------------------------

--- Batch-fetch sub-issue counts via GraphQL aliases.
---@param issue_numbers integer[]
---@param callback fun(counts: table<integer, {total: integer, completed: integer}>)
function M.fetch_sub_issue_counts(issue_numbers, callback)
  if not issue_numbers or #issue_numbers == 0 then
    callback({})
    return
  end

  local api = require("okuban.api")
  api.detect_repo_info(function(owner, name)
    if not owner or not name then
      callback({})
      return
    end

    -- Build batched alias query (chunks of 25 to avoid oversized queries)
    local all_counts = {}
    local chunks = {}
    for i = 1, #issue_numbers, 25 do
      local chunk = {}
      for j = i, math.min(i + 24, #issue_numbers) do
        table.insert(chunk, issue_numbers[j])
      end
      table.insert(chunks, chunk)
    end

    local pending = #chunks
    if pending == 0 then
      callback({})
      return
    end

    for _, chunk in ipairs(chunks) do
      local aliases = {}
      for _, num in ipairs(chunk) do
        table.insert(
          aliases,
          string.format("i%d: issue(number: %d) { subIssuesSummary { total completed } }", num, num)
        )
      end

      local query =
        string.format('{ repository(owner: "%s", name: "%s") { %s } }', owner, name, table.concat(aliases, " "))

      local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
        "api",
        "graphql",
        "-H",
        "GraphQL-Features: sub_issues",
        "-f",
        "query=" .. query,
      })

      vim.system(cmd, { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 and result.stdout then
            local ok, data = pcall(vim.json.decode, result.stdout)
            if ok and data and data.data and data.data.repository then
              local repo = data.data.repository
              for _, num in ipairs(chunk) do
                local key = "i" .. num
                if repo[key] and repo[key].subIssuesSummary then
                  local s = repo[key].subIssuesSummary
                  if s.total and s.total > 0 then
                    all_counts[num] = { total = s.total, completed = s.completed or 0 }
                  end
                end
              end
            end
          end

          pending = pending - 1
          if pending == 0 then
            callback(all_counts)
          end
        end)
      end)
    end
  end)
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

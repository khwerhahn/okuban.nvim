local config = require("okuban.config")
local utils = require("okuban.utils")

local M = {}

--- Session-level cache for preflight results.
local preflight_passed = false

--- Build the gh command prefix, respecting github_hostname config.
---@return string[]
local function gh_base_cmd()
  local hostname = config.get().github_hostname
  if hostname then
    return { "gh", "--hostname", hostname }
  end
  return { "gh" }
end

--- Check if gh CLI is installed (synchronous).
---@return boolean
function M.check_gh_installed()
  return utils.is_executable("gh")
end

--- Check if gh CLI is authenticated.
---@param callback fun(ok: boolean, err: string|nil)
function M.check_gh_auth(callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), { "auth", "status" })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, "Not authenticated. Run: gh auth login")
      end
    end)
  end)
end

--- Check if we have repo access in the current directory.
---@param callback fun(ok: boolean, err: string|nil)
function M.check_repo_access(callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), { "repo", "view", "--json", "name", "-q", ".name" })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 and result.stdout and result.stdout:match("%S") then
        callback(true, nil)
      else
        local msg = "Cannot access repository. Ensure you are in a git repo with a GitHub remote"
        if result.stderr and result.stderr:match("scope") then
          msg = "Insufficient GitHub permissions. Run: gh auth refresh -s repo"
        end
        callback(false, msg)
      end
    end)
  end)
end

--- Run all preflight checks in sequence.
--- Calls callback(true) on success, or notifies error and calls callback(false).
---@param callback fun(ok: boolean)
function M.preflight(callback)
  if config.get().skip_preflight then
    callback(true)
    return
  end

  if preflight_passed then
    callback(true)
    return
  end

  -- Step 1: gh installed (sync)
  if not M.check_gh_installed() then
    utils.notify("gh CLI not found. Install from https://cli.github.com", vim.log.levels.ERROR)
    callback(false)
    return
  end

  -- Step 2: gh authenticated (async)
  M.check_gh_auth(function(ok, err)
    if not ok then
      utils.notify(err, vim.log.levels.ERROR)
      callback(false)
      return
    end

    -- Step 3: repo access (async)
    M.check_repo_access(function(repo_ok, repo_err)
      if not repo_ok then
        utils.notify(repo_err, vim.log.levels.ERROR)
        callback(false)
        return
      end

      preflight_passed = true
      callback(true)
    end)
  end)
end

--- Reset preflight cache (for testing).
function M._reset_preflight()
  preflight_passed = false
end

--- Expose gh_base_cmd for other api functions.
---@return string[]
function M._gh_base_cmd()
  return gh_base_cmd()
end

-- ---------------------------------------------------------------------------
-- Fetch issues
-- ---------------------------------------------------------------------------

local ISSUE_FIELDS = "number,title,assignees,labels,state"

--- Fetch issues for a single label.
---@param label string The label to filter by
---@param callback fun(issues: table[]|nil, err: string|nil)
function M.fetch_column(label, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "list",
    "--label",
    label,
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
  local cfg = config.get()
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
        })
      end
      if cfg.show_unsorted then
        board_data.unsorted = results["_unsorted"] or {}
      end
      callback(board_data)
    end
  end

  -- Fire all column fetches in parallel
  for _, col in ipairs(columns) do
    M.fetch_column(col.label, function(issues, err)
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

return M

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

--- Check if we have project scope (lazy, only when source="project").
---@param callback fun(ok: boolean, err: string|nil)
function M.check_project_scope(callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "project",
    "list",
    "--limit",
    "1",
    "--format",
    "json",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, "GitHub Projects requires additional permissions. Run: gh auth refresh -s project")
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

-- ---------------------------------------------------------------------------
-- Repo info detection (cached)
-- ---------------------------------------------------------------------------

local repo_info_cache = nil ---@type {owner: string, name: string}|nil

--- Detect the repo owner and name (cached).
---@param callback fun(owner: string|nil, name: string|nil)
function M.detect_repo_info(callback)
  if repo_info_cache then
    callback(repo_info_cache.owner, repo_info_cache.name)
    return
  end
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "repo",
    "view",
    "--json",
    "owner,name",
    "-q",
    '.owner.login + "|" + .name',
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 and result.stdout then
        local owner, name = vim.trim(result.stdout):match("^(.+)|(.+)$")
        if owner and name then
          repo_info_cache = { owner = owner, name = name }
          callback(owner, name)
          return
        end
      end
      callback(nil, nil)
    end)
  end)
end

--- Reset repo info cache (for testing).
function M._reset_repo_info()
  repo_info_cache = nil
end

--- Expose gh_base_cmd for other api modules.
---@return string[]
function M._gh_base_cmd()
  return gh_base_cmd()
end

-- ---------------------------------------------------------------------------
-- Routed functions — delegate based on config.source
-- ---------------------------------------------------------------------------

--- Edit labels on an issue (remove one, add another).
--- Label-mode only. In project mode, use move_card() instead.
---@param number integer Issue number
---@param remove_label string Label to remove
---@param add_label string Label to add
---@param callback fun(ok: boolean, err: string|nil)
function M.edit_labels(number, remove_label, add_label, callback)
  return require("okuban.api_labels").edit_labels(number, remove_label, add_label, callback)
end

--- Return cached board data if fresh enough. Routes based on config.source.
---@param max_age integer Maximum cache age in seconds
---@return table|nil board_data
function M.get_cached_board_data(max_age)
  if config.get().source == "project" then
    return require("okuban.api_project").get_cached_board_data(max_age)
  end
  return require("okuban.api_labels").get_cached_board_data(max_age)
end

--- Fetch all columns and return structured board data.
--- Routes to api_labels or api_project based on config.source.
---@param callback fun(data: table|nil)
function M.fetch_all_columns(callback)
  if config.get().source == "project" then
    return require("okuban.api_project").fetch_all_columns(callback)
  end
  return require("okuban.api_labels").fetch_all_columns(callback)
end

--- Expand a column by fetching more issues. Routes based on config.source.
---@param col_index integer Column index in board_data.columns (1-based)
---@param callback fun(ok: boolean, err: string|nil)
function M.expand_column(col_index, callback)
  if config.get().source == "project" then
    return require("okuban.api_project").expand_column(col_index, callback)
  end
  return require("okuban.api_labels").expand_column(col_index, callback)
end

--- Fetch sub-issue counts for a list of issue numbers. Routes based on source.
--- In project mode, counts are embedded in issue objects (no extra call needed).
---@param issue_numbers integer[]
---@param callback fun(counts: table<integer, {total: integer, completed: integer}>)
function M.fetch_sub_issue_counts(issue_numbers, callback)
  if config.get().source == "project" then
    callback({})
    return
  end
  return require("okuban.api_labels").fetch_sub_issue_counts(issue_numbers, callback)
end

--- Fetch issues for a single label (label-mode only).
---@param label string The label to filter by
---@param state string|nil Issue state filter
---@param limit integer|nil Max issues to fetch
---@param callback fun(issues: table[]|nil, err: string|nil)
function M.fetch_column(label, state, limit, callback)
  return require("okuban.api_labels").fetch_column(label, state, limit, callback)
end

--- Fetch unsorted issues (label-mode only).
---@param columns table[] The configured columns
---@param callback fun(issues: table[]|nil, err: string|nil)
function M.fetch_unsorted(columns, callback)
  return require("okuban.api_labels").fetch_unsorted(columns, callback)
end

--- Move a card between columns. Routes based on config.source.
---@param number integer Issue number
---@param from_id string Current column identifier (label name or status option ID)
---@param to_id string Target column identifier (label name or status option ID)
---@param _to_name string Target column display name (unused, for caller context)
---@param callback fun(ok: boolean, err: string|nil)
function M.move_card(number, from_id, to_id, _to_name, callback)
  if config.get().source == "project" then
    local proj = require("okuban.api_project")
    local item_id = proj.get_item_id(number)
    if not item_id then
      callback(false, "Issue #" .. number .. " not found in project")
      return
    end
    local field = proj.get_cached_status_field()
    local project_id = proj.get_cached_project_id()
    if not field or not project_id then
      callback(false, "Project metadata not loaded")
      return
    end
    proj.move_item(item_id, project_id, field.id, to_id, callback)
  else
    return require("okuban.api_labels").edit_labels(number, from_id, to_id, callback)
  end
end

-- ---------------------------------------------------------------------------
-- Label management (label-mode only)
-- ---------------------------------------------------------------------------

--- Create a single label on the repo (idempotent via --force).
---@param label table { name, color, description }
---@param callback fun(ok: boolean)
function M.create_label(label, callback)
  return require("okuban.api_labels").create_label(label, callback)
end

--- Create all labels for OkubanSetup.
---@param full boolean If true, create all labels including type/priority/community
---@param callback fun(created: integer, failed: integer)
function M.create_all_labels(full, callback)
  return require("okuban.api_labels").create_all_labels(full, callback)
end

-- ---------------------------------------------------------------------------
-- Issue operations (shared, source-agnostic)
-- ---------------------------------------------------------------------------

--- Close a GitHub issue.
---@param number integer Issue number
---@param callback fun(ok: boolean, err: string|nil)
function M.close_issue(number, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "close",
    tostring(number),
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, result.stderr or "Failed to close issue")
      end
    end)
  end)
end

--- Assign an issue to the current user.
---@param number integer Issue number
---@param callback fun(ok: boolean, err: string|nil)
function M.assign_issue(number, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "edit",
    tostring(number),
    "--add-assignee",
    "@me",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, result.stderr or "Failed to assign issue")
      end
    end)
  end)
end

--- Create a new GitHub issue.
---@param title string
---@param body string
---@param labels string[]
---@param callback fun(ok: boolean, number: integer|nil, err: string|nil, url: string|nil)
function M.create_issue(title, body, labels, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "create",
    "--title",
    title,
    "--body",
    body,
  })
  for _, label in ipairs(labels or {}) do
    vim.list_extend(cmd, { "--label", label })
  end
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 and result.stdout then
        -- gh issue create prints the URL: https://github.com/owner/repo/issues/42
        local url = vim.trim(result.stdout)
        local number = url:match("/issues/(%d+)")
        if number then
          callback(true, tonumber(number), nil, url)
          return
        end
        callback(true, nil, nil, url)
      else
        callback(false, nil, result.stderr or "Failed to create issue", nil)
      end
    end)
  end)
end

--- Open an issue in the system browser.
---@param number integer Issue number
function M.view_issue_in_browser(number)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "issue",
    "view",
    tostring(number),
    "--web",
  })
  vim.system(cmd, { text = true })
end

return M

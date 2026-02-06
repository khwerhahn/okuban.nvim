local config = require("okuban.config")

local M = {}

--- Parse the current git branch name for an issue number.
--- Supports patterns like:
---   feat/issue-42-description → 42
---   fix/123-null-check → 123
---   42-add-login → 42
---   GH-42-oauth → 42
---   feature/issue-42 → 42
---@return integer|nil issue_number
function M.detect_from_branch()
  local result = vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout then
    return nil
  end
  local branch = vim.trim(result.stdout)
  if branch == "" or branch == "HEAD" then
    return nil
  end
  return M.parse_branch_name(branch)
end

--- Extract an issue number from a branch name string.
---@param branch string
---@return integer|nil
function M.parse_branch_name(branch)
  -- Pattern 1: explicit "issue-N" anywhere in the branch name
  local num = branch:match("issue%-(%d+)")
  if num then
    return tonumber(num)
  end

  -- Pattern 2: GH-N or gh-N prefix
  num = branch:match("[Gg][Hh]%-(%d+)")
  if num then
    return tonumber(num)
  end

  -- Pattern 3: type/N-description (e.g. feat/42-login, fix/123-null)
  num = branch:match("^%a+/(%d+)")
  if num then
    return tonumber(num)
  end

  -- Pattern 4: bare N-description at start (e.g. 42-add-login)
  num = branch:match("^(%d+)%-")
  if num then
    return tonumber(num)
  end

  return nil
end

--- Scan recent commit messages for issue references.
--- Looks for #N, Fixes #N, Closes #N, Refs #N, Resolves #N.
--- Returns the most-referenced issue number, or nil.
---@param max_commits integer|nil Number of commits to scan (default: 5)
---@return integer|nil issue_number
function M.detect_from_commits(max_commits)
  max_commits = max_commits or 5
  local result = vim
    .system({ "git", "log", "--oneline", "-n", tostring(max_commits), "--format=%s" }, { text = true })
    :wait()
  if result.code ~= 0 or not result.stdout then
    return nil
  end
  return M.parse_commit_messages(result.stdout)
end

--- Extract the most-referenced issue number from commit message text.
---@param text string Newline-separated commit subjects
---@return integer|nil
function M.parse_commit_messages(text)
  local counts = {}
  for num in text:gmatch("#(%d+)") do
    local n = tonumber(num)
    if n then
      counts[n] = (counts[n] or 0) + 1
    end
  end

  local best_num = nil
  local best_count = 0
  for num, count in pairs(counts) do
    if count > best_count then
      best_count = count
      best_num = num
    end
  end
  return best_num
end

--- Async: query gh CLI for the user's in-progress issues.
--- Returns the first issue number assigned to @me with okuban:in-progress label.
---@param callback fun(issue_number: integer|nil)
function M.detect_from_gh(callback)
  local cfg = config.get()
  local hostname = cfg.github_hostname
  local cmd = hostname and { "gh", "--hostname", hostname } or { "gh" }
  vim.list_extend(cmd, {
    "issue",
    "list",
    "--assignee",
    "@me",
    "--state",
    "open",
    "--label",
    "okuban:in-progress",
    "--json",
    "number",
    "--limit",
    "1",
  })

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 or not result.stdout then
        callback(nil)
        return
      end
      local ok, issues = pcall(vim.json.decode, result.stdout)
      if not ok or type(issues) ~= "table" or #issues == 0 then
        callback(nil)
        return
      end
      callback(issues[1].number)
    end)
  end)
end

--- Run the full detection cascade and call back with the best issue number.
--- Tier 1 (branch) and Tier 2 (commits) are synchronous.
--- Tier 3 (gh CLI) is async and only used if Tiers 1+2 fail.
---@param callback fun(issue_number: integer|nil)
function M.detect_issue(callback)
  -- Tier 1: branch name (instant)
  local num = M.detect_from_branch()
  if num then
    callback(num)
    return
  end

  -- Tier 2: commit messages (fast)
  num = M.detect_from_commits()
  if num then
    callback(num)
    return
  end

  -- Tier 3: gh CLI (async)
  M.detect_from_gh(callback)
end

return M

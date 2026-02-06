local detect = require("okuban.detect")

local M = {}

--- Parse the output of `git worktree list --porcelain` into structured data.
---@param output string Raw output from git worktree list --porcelain
---@return table[] worktrees Array of { path, head, branch, bare, detached }
function M.parse_porcelain(output)
  if not output or output == "" then
    return {}
  end

  local worktrees = {}
  local current = {}

  for line in (output .. "\n"):gmatch("([^\n]*)\n") do
    if line == "" then
      if current.path then
        table.insert(worktrees, current)
      end
      current = {}
    elseif line:match("^worktree ") then
      current.path = line:sub(10)
    elseif line:match("^HEAD ") then
      current.head = line:sub(6)
    elseif line:match("^branch ") then
      -- Strip refs/heads/ prefix
      local branch = line:sub(8)
      current.branch = branch:gsub("^refs/heads/", "")
    elseif line == "bare" then
      current.bare = true
    elseif line == "detached" then
      current.detached = true
    end
  end

  -- Handle last entry if no trailing newline
  if current.path then
    table.insert(worktrees, current)
  end

  return worktrees
end

--- Map worktrees to issue numbers using branch name detection.
--- Returns a table keyed by issue number.
---@param worktrees table[] Parsed worktree list
---@return table<integer, table> map { [issue_number] = { path, branch, ... } }
function M.map_to_issues(worktrees)
  local map = {}
  for _, wt in ipairs(worktrees) do
    if wt.branch and not wt.bare then
      local num = detect.parse_branch_name(wt.branch)
      if num then
        map[num] = wt
      end
    end
  end
  return map
end

--- Fetch the list of worktrees and map them to issue numbers.
--- Synchronous (~4ms).
---@return table<integer, table> map { [issue_number] = { path, branch, dirty, active } }
function M.fetch_worktree_map()
  local result = vim.system({ "git", "worktree", "list", "--porcelain" }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout then
    return {}
  end

  local worktrees = M.parse_porcelain(result.stdout)
  local map = M.map_to_issues(worktrees)

  -- Mark the active worktree (matches current cwd)
  local cwd = vim.fn.getcwd()
  for _, wt in pairs(map) do
    wt.active = (wt.path == cwd)
  end

  return map
end

--- Check dirty/clean status of a single worktree (async).
---@param path string Worktree path
---@param callback fun(dirty: boolean)
function M.check_dirty(path, callback)
  vim.system({ "git", "-C", path, "status", "--porcelain" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(false)
        return
      end
      local dirty = result.stdout and result.stdout:match("%S") ~= nil
      callback(dirty)
    end)
  end)
end

--- Fetch worktree map and enrich with dirty/clean status (async).
--- Calls callback with the fully enriched map.
---@param callback fun(map: table<integer, table>)
function M.fetch_enriched(callback)
  local map = M.fetch_worktree_map()

  -- Count how many worktrees need status checks
  local pending = 0
  for _ in pairs(map) do
    pending = pending + 1
  end

  if pending == 0 then
    callback(map)
    return
  end

  for _, wt in pairs(map) do
    M.check_dirty(wt.path, function(dirty)
      wt.dirty = dirty
      pending = pending - 1
      if pending == 0 then
        callback(map)
      end
    end)
  end
end

return M

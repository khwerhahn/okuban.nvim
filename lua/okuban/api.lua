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

return M

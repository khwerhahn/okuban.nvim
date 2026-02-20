local M = {}

local health = vim.health

--- Run a synchronous command and return the result.
---@param cmd string[]
---@return vim.SystemCompleted
local function run(cmd)
  return vim.system(cmd, { text = true }):wait()
end

--- Build the gh command prefix, respecting github_hostname config.
---@return string[]
local function gh_base_cmd()
  local ok, config = pcall(require, "okuban.config")
  if ok then
    local hostname = config.get().github_hostname
    if hostname then
      return { "gh", "--hostname", hostname }
    end
  end
  return { "gh" }
end

function M.check()
  health.start("okuban.nvim")

  -- 1. Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ required", { "Update Neovim: https://github.com/neovim/neovim/blob/master/INSTALL.md" })
  end

  -- 2. gh CLI installed
  if vim.fn.executable("gh") ~= 1 then
    health.error("`gh` CLI not found", { "Install from https://cli.github.com" })
    return
  end
  local gh_ver = run({ "gh", "--version" })
  local version_str = gh_ver.stdout and gh_ver.stdout:match("gh version ([%d%.]+)") or "unknown"
  health.ok("`gh` CLI installed (v" .. version_str .. ")")

  -- 3. gh authenticated
  local base = gh_base_cmd()
  local auth = run(vim.list_extend(vim.deepcopy(base), { "auth", "status" }))
  if auth.code == 0 then
    health.ok("`gh` authenticated")
  else
    health.error("`gh` not authenticated", { "Run: gh auth login" })
    return
  end

  -- 4. Repository access
  local repo = run(vim.list_extend(vim.deepcopy(base), { "repo", "view", "--json", "name", "-q", ".name" }))
  if repo.code == 0 and repo.stdout and repo.stdout:match("%S") then
    health.ok("Repository accessible: " .. vim.trim(repo.stdout))
  else
    health.warn("Not in a GitHub repository (or no remote configured)", {
      "Run from a directory with a GitHub remote",
    })
  end

  -- 5. okuban labels
  if repo.code == 0 then
    local labels = run(vim.list_extend(vim.deepcopy(base), {
      "label",
      "list",
      "--search",
      "okuban:",
      "--json",
      "name",
      "-q",
      ".[].name",
    }))
    if labels.code == 0 and labels.stdout and labels.stdout:match("okuban:") then
      local count = select(2, labels.stdout:gsub("okuban:", ""))
      health.ok("okuban labels found (" .. count .. ")")
    else
      health.warn("No `okuban:` labels found on this repo", { "Run :OkubanSetup to create them" })
    end
  end

  -- 6. Claude CLI (optional)
  if vim.fn.executable("claude") == 1 then
    health.ok("`claude` CLI available (autonomous coding enabled)")
  else
    health.info("`claude` CLI not found (autonomous coding disabled)", {
      "Optional — install from https://claude.ai/code",
    })
  end

  -- 7. tmux (optional)
  if vim.fn.executable("tmux") == 1 then
    local in_tmux = vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
    if in_tmux then
      health.ok("`tmux` available (currently inside tmux)")
    else
      health.ok("`tmux` available (not currently inside tmux)")
    end
  else
    health.info("`tmux` not found (Claude will use headless mode)", {
      "Optional — install tmux for interactive Claude sessions",
    })
  end
end

return M

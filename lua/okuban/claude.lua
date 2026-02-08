local config = require("okuban.config")
local utils = require("okuban.utils")

local M = {}

-- Module-local state
local active_sessions = {} ---@type table<integer, table>
local claude_checked = nil ---@type boolean|nil nil=unchecked

--- Reset module state (for tests).
function M._reset()
  active_sessions = {}
  claude_checked = nil
end

--- Check if the `claude` CLI is installed (result is cached).
---@return boolean
function M.is_available()
  if claude_checked ~= nil then
    return claude_checked
  end
  claude_checked = vim.fn.executable("claude") == 1
  return claude_checked
end

--- Lazy auth verification — runs `claude --version` to confirm CLI works.
--- Only checks once per session; subsequent calls invoke callback immediately.
---@param callback fun(ok: boolean, err: string|nil)
function M.check_auth(callback)
  -- is_available already checks executable; this validates it actually runs
  if not M.is_available() then
    callback(false, "claude CLI not found")
    return
  end

  vim.system({ "claude", "--version" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, "claude CLI check failed: " .. (result.stderr or ""))
      end
    end)
  end)
end

--- Get the git repo root path.
---@return string|nil
function M.get_repo_root()
  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    return vim.trim(result.stdout)
  end
  return nil
end

--- Compute the worktree path for a given issue number.
---@param issue_number integer
---@return string|nil path, string|nil error
function M.worktree_path(issue_number)
  local cfg = config.get().claude
  if cfg.worktree_base_dir then
    return cfg.worktree_base_dir .. "/issue-" .. issue_number, nil
  end

  local root = M.get_repo_root()
  if not root then
    return nil, "Could not determine git repo root"
  end

  -- Place worktrees in {repo-root}-worktrees/ (sibling of repo)
  return root .. "-worktrees/issue-" .. issue_number, nil
end

--- Check if a worktree already exists for this issue.
---@param issue_number integer
---@return string|nil worktree_path Path if exists, nil otherwise
function M.find_existing_worktree(issue_number)
  local wt_path = M.worktree_path(issue_number)
  if not wt_path then
    return nil
  end

  local result = vim.system({ "git", "worktree", "list", "--porcelain" }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout then
    return nil
  end

  for line in result.stdout:gmatch("[^\n]+") do
    local path = line:match("^worktree (.+)")
    if path and path == wt_path then
      return wt_path
    end
  end

  return nil
end

--- Create a git worktree for the given issue (async).
---@param issue_number integer
---@param callback fun(ok: boolean, path: string|nil, err: string|nil)
function M.create_worktree(issue_number, callback)
  local wt_path, err = M.worktree_path(issue_number)
  if not wt_path then
    callback(false, nil, err)
    return
  end

  -- Check if already exists
  local existing = M.find_existing_worktree(issue_number)
  if existing then
    callback(true, existing, nil)
    return
  end

  local branch = "feat/issue-" .. issue_number .. "-claude"

  -- Try creating worktree with new branch
  vim.system({ "git", "worktree", "add", "-b", branch, wt_path }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, wt_path, nil)
        return
      end

      -- Branch may already exist — try without -b
      vim.system({ "git", "worktree", "add", wt_path, branch }, { text = true }, function(result2)
        vim.schedule(function()
          if result2.code == 0 then
            callback(true, wt_path, nil)
          else
            callback(false, nil, "Failed to create worktree: " .. (result2.stderr or ""))
          end
        end)
      end)
    end)
  end)
end

--- Fetch issue context via gh CLI (async).
---@param issue_number integer
---@param callback fun(context: table|nil, err: string|nil)
function M.fetch_issue_context(issue_number, callback)
  local cmd = { "gh", "issue", "view", tostring(issue_number), "--json", "number,title,body,labels,comments" }
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "gh issue view failed: " .. (result.stderr or ""))
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or not data then
        callback(nil, "Failed to parse issue JSON")
        return
      end

      callback(data, nil)
    end)
  end)
end

--- Build the prompt string for Claude from issue context.
---@param issue_number integer
---@param context table Issue context from fetch_issue_context
---@return string
function M.build_prompt(issue_number, context)
  local parts = {
    "You are working on GitHub issue #" .. issue_number .. ".",
    "",
    "## Issue: " .. (context.title or ""),
    "",
  }

  if context.body and context.body ~= "" then
    table.insert(parts, "## Description")
    table.insert(parts, context.body)
    table.insert(parts, "")
  end

  if context.labels and #context.labels > 0 then
    local label_names = {}
    for _, lbl in ipairs(context.labels) do
      table.insert(label_names, lbl.name)
    end
    table.insert(parts, "Labels: " .. table.concat(label_names, ", "))
    table.insert(parts, "")
  end

  if context.comments and #context.comments > 0 then
    table.insert(parts, "## Recent Comments")
    local max_comments = math.min(5, #context.comments)
    for i = #context.comments - max_comments + 1, #context.comments do
      local comment = context.comments[i]
      if comment.body then
        table.insert(parts, "---")
        table.insert(parts, comment.body)
      end
    end
    table.insert(parts, "")
  end

  table.insert(parts, "Implement the changes described in this issue. Write tests if appropriate.")
  table.insert(parts, "When done, commit your changes with a message referencing Fixes #" .. issue_number .. ".")

  return table.concat(parts, "\n")
end

--- Build the claude CLI command arguments.
---@param prompt string
---@param wt_path string Worktree path (used as cwd, not in command)
---@return string[]
function M.build_command(prompt, wt_path) -- luacheck: no unused args
  local cfg = config.get().claude
  local cmd = {
    "claude",
    "-p",
    prompt,
    "--output-format",
    "stream-json",
    "--max-budget-usd",
    tostring(cfg.max_budget_usd),
  }

  -- Add allowed tools
  if cfg.allowed_tools and #cfg.allowed_tools > 0 then
    for _, tool in ipairs(cfg.allowed_tools) do
      table.insert(cmd, "--allowedTools")
      table.insert(cmd, tool)
    end
  end

  return cmd
end

--- Parse a single stream-json line into a structured event.
---@param line string
---@return table|nil event { type, subtype, ... } or nil if not valid
function M.parse_stream_event(line)
  if not line or line == "" then
    return nil
  end

  local ok, data = pcall(vim.json.decode, line)
  if not ok or type(data) ~= "table" then
    return nil
  end

  return data
end

--- Handle a stream event for a session (must be called from main loop via vim.schedule).
---@param issue_number integer
---@param event table Parsed stream event
local function handle_event(issue_number, event)
  vim.schedule(function()
    local session = active_sessions[issue_number]
    if not session then
      return
    end

    if event.type == "system" and event.subtype == "init" then
      session.session_id = event.session_id
    elseif event.type == "assistant" then
      session.turns = (session.turns or 0) + 1
    elseif event.type == "result" then
      session.cost_usd = event.total_cost_usd
      session.num_turns = event.num_turns
      if event.is_error then
        session.status = "failed"
      else
        session.status = "completed"
      end

      local cost_str = session.cost_usd and string.format("$%.2f", session.cost_usd) or "unknown cost"
      local turns_str = session.num_turns and (session.num_turns .. " turns") or ""
      utils.notify(
        string.format(
          "Claude finished #%d (%s%s%s)",
          issue_number,
          session.status,
          cost_str ~= "unknown cost" and (", " .. cost_str) or "",
          turns_str ~= "" and (", " .. turns_str) or ""
        )
      )
    end
  end)
end

--- Launch an autonomous Claude session for an issue.
---@param issue table { number: integer, title: string }
---@param callback fun(ok: boolean, err: string|nil)|nil
function M.launch(issue, callback)
  callback = callback or function() end
  local issue_number = issue.number

  if not M.is_available() then
    callback(false, "claude CLI not found — install it to use autonomous coding")
    return
  end

  -- Check for existing running/initializing session
  local existing = active_sessions[issue_number]
  if existing and (existing.status == "running" or existing.status == "initializing") then
    utils.notify("Claude is already working on #" .. issue_number)
    callback(false, "Session already running")
    return
  end

  -- Reserve the slot immediately to prevent race conditions
  active_sessions[issue_number] = { status = "initializing" }
  local stop = utils.spinner_start("Launching Claude for #" .. issue_number .. "...")

  -- Auth check (lazy, first use)
  M.check_auth(function(auth_ok, auth_err)
    if not auth_ok then
      active_sessions[issue_number] = nil
      stop(auth_err)
      callback(false, auth_err)
      return
    end

    utils.spinner_update("Creating worktree...")
    -- Create worktree
    M.create_worktree(issue_number, function(wt_ok, wt_path, wt_err)
      if not wt_ok or not wt_path then
        active_sessions[issue_number] = nil
        stop(wt_err or "Failed to create worktree")
        callback(false, wt_err or "Failed to create worktree")
        return
      end

      utils.spinner_update("Fetching issue context...")
      -- Fetch issue context
      M.fetch_issue_context(issue_number, function(context, ctx_err)
        if not context then
          active_sessions[issue_number] = nil
          stop(ctx_err or "Failed to fetch issue context")
          callback(false, ctx_err or "Failed to fetch issue context")
          return
        end

        local prompt = M.build_prompt(issue_number, context)
        local cmd = M.build_command(prompt, wt_path)

        -- Launch via jobstart for streaming stdout
        -- jobstart on_stdout receives data as a list of lines split by newlines.
        -- The last element may be incomplete (no trailing newline).
        local buffer = ""
        local job_id = vim.fn.jobstart(cmd, {
          cwd = wt_path,
          on_stdout = function(_, data, _)
            if not data or #data == 0 then
              return
            end
            -- First chunk continues any incomplete line from previous call
            data[1] = buffer .. data[1]
            -- Process all complete lines (all but the last)
            for i = 1, #data - 1 do
              local line = data[i]
              if line and line ~= "" then
                local event = M.parse_stream_event(line)
                if event then
                  handle_event(issue_number, event)
                end
              end
            end
            -- Last element may be incomplete — save for next callback
            buffer = data[#data] or ""
          end,
          on_stderr = function(_, data, _)
            if not data then
              return
            end
            for _, line in ipairs(data) do
              if line and line ~= "" then
                vim.schedule(function()
                  utils.notify("claude: " .. line, vim.log.levels.DEBUG)
                end)
              end
            end
          end,
          on_exit = function(_, exit_code, _)
            vim.schedule(function()
              local session = active_sessions[issue_number]
              if session and session.status == "running" then
                -- If we didn't get a result event, mark based on exit code
                session.status = (exit_code == 0) and "completed" or "failed"
                utils.notify(
                  string.format("Claude finished #%d (%s, exit %d)", issue_number, session.status, exit_code)
                )
              end
            end)
          end,
        })

        if job_id <= 0 then
          active_sessions[issue_number] = nil
          stop("Failed to start claude process")
          callback(false, "Failed to start claude process")
          return
        end

        active_sessions[issue_number] = {
          job_id = job_id,
          session_id = nil,
          worktree_path = wt_path,
          status = "running",
          turns = 0,
          cost_usd = nil,
          num_turns = nil,
          started_at = os.time(),
        }

        stop("Claude started on #" .. issue_number)
        callback(true, nil)
      end)
    end)
  end)
end

--- Get session info for a specific issue.
---@param issue_number integer
---@return table|nil session
function M.get_session(issue_number)
  return active_sessions[issue_number]
end

--- Get all active sessions.
---@return table<integer, table>
function M.get_all_sessions()
  return active_sessions
end

--- Stop a running Claude session.
---@param issue_number integer
---@return boolean success
function M.stop(issue_number)
  local session = active_sessions[issue_number]
  if not session or session.status ~= "running" then
    return false
  end

  vim.fn.jobstop(session.job_id)
  session.status = "failed"
  utils.notify("Stopped Claude session for #" .. issue_number)
  return true
end

return M

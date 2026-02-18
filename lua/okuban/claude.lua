local config = require("okuban.config")
local utils = require("okuban.utils")

local M = {}

local active_sessions = {} ---@type table<integer, table>
local claude_checked = nil ---@type boolean|nil nil=unchecked

function M._reset()
  active_sessions = {}
  claude_checked = nil
end
---@return boolean
function M.is_available()
  if claude_checked ~= nil then
    return claude_checked
  end
  claude_checked = vim.fn.executable("claude") == 1
  return claude_checked
end
function M.check_auth(callback)
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
function M.get_repo_root()
  local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    return vim.trim(result.stdout)
  end
  return nil
end
function M.worktree_path(issue_number)
  local cfg = config.get().claude
  if cfg.worktree_base_dir then
    return cfg.worktree_base_dir .. "/issue-" .. issue_number, nil
  end

  local root = M.get_repo_root()
  if not root then
    return nil, "Could not determine git repo root"
  end

  return root .. "-worktrees/issue-" .. issue_number, nil
end
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
function M.create_worktree(issue_number, callback)
  local wt_path, err = M.worktree_path(issue_number)
  if not wt_path then
    callback(false, nil, err)
    return
  end
  local existing = M.find_existing_worktree(issue_number)
  if existing then
    callback(true, existing, nil)
    return
  end
  local branch = "feat/issue-" .. issue_number .. "-claude"
  vim.system({ "git", "worktree", "add", "-b", branch, wt_path }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, wt_path, nil)
        return
      end

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
  return table.concat(parts, "\n")
end
function M.build_system_prompt(issue_number)
  return "All commits must include 'Fixes #"
    .. issue_number
    .. "' or 'Refs #"
    .. issue_number
    .. "' in the message. Follow the project's CLAUDE.md conventions."
end
function M.build_command(prompt, issue_number, opts)
  opts = opts or {}
  local stream_json = opts.stream_json ~= false
  local cfg = config.get().claude
  local cmd = {
    "claude",
    "-p",
    prompt,
    "--dangerously-skip-permissions",
    "--max-turns",
    tostring(cfg.max_turns),
    "--max-budget-usd",
    tostring(cfg.max_budget_usd),
  }

  if stream_json then
    table.insert(cmd, "--output-format")
    table.insert(cmd, "stream-json")
  end

  if cfg.model then
    table.insert(cmd, "--model")
    table.insert(cmd, cfg.model)
  end

  if issue_number then
    table.insert(cmd, "--append-system-prompt")
    table.insert(cmd, M.build_system_prompt(issue_number))
  end

  if cfg.agent_teams and cfg.agent_teams.enabled then
    table.insert(cmd, "--teammate-mode")
    table.insert(cmd, cfg.agent_teams.teammate_mode or "tmux")
  end

  if cfg.allowed_tools and #cfg.allowed_tools > 0 then
    for _, tool in ipairs(cfg.allowed_tools) do
      table.insert(cmd, "--allowedTools")
      table.insert(cmd, tool)
    end
  end

  return cmd
end
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
function M.launch(issue, callback)
  callback = callback or function() end
  local issue_number = issue.number
  if not M.is_available() then
    callback(false, "claude CLI not found — install it to use autonomous coding")
    return
  end

  local existing = active_sessions[issue_number]
  if existing and (existing.status == "running" or existing.status == "initializing") then
    utils.notify("Claude is already working on #" .. issue_number)
    callback(false, "Session already running")
    return
  end

  active_sessions[issue_number] = { status = "initializing" }
  local stop = utils.spinner_start("Launching Claude for #" .. issue_number .. "...")

  M.check_auth(function(auth_ok, auth_err)
    if not auth_ok then
      active_sessions[issue_number] = nil
      stop(auth_err)
      callback(false, auth_err)
      return
    end

    utils.spinner_update("Creating worktree...")
    M.create_worktree(issue_number, function(wt_ok, wt_path, wt_err)
      if not wt_ok or not wt_path then
        active_sessions[issue_number] = nil
        stop(wt_err or "Failed to create worktree")
        callback(false, wt_err or "Failed to create worktree")
        return
      end

      utils.spinner_update("Fetching issue context...")
      M.fetch_issue_context(issue_number, function(context, ctx_err)
        if not context then
          active_sessions[issue_number] = nil
          stop(ctx_err or "Failed to fetch issue context")
          callback(false, ctx_err or "Failed to fetch issue context")
          return
        end

        local prompt = M.build_prompt(issue_number, context)
        local cfg = config.get().claude
        local cmd = M.build_command(prompt, issue_number)
        local launch_mode = cfg.launch_mode
        if cfg.agent_teams and cfg.agent_teams.enabled then
          launch_mode = "tmux"
        elseif launch_mode == "auto" then
          local tmux = require("okuban.tmux")
          launch_mode = tmux.is_available() and "tmux" or "headless"
        end

        if launch_mode == "tmux" then
          M._launch_tmux(issue_number, cmd, wt_path, stop, callback)
        else
          M._launch_headless(issue_number, cmd, wt_path, stop, callback)
        end
      end)
    end)
  end)
end
function M._launch_headless(issue_number, cmd, wt_path, stop, callback)
  -- Create session object BEFORE jobstart to avoid race condition:
  -- on_exit can fire before post-jobstart code runs if the process exits immediately.
  -- By capturing `session` in the closures, we guarantee they update the same object.
  local session = {
    job_id = nil,
    session_id = nil,
    worktree_path = wt_path,
    status = "running",
    turns = 0,
    cost_usd = nil,
    num_turns = nil,
    started_at = os.time(),
  }
  active_sessions[issue_number] = session

  local buffer = ""
  local job_id = vim.fn.jobstart(cmd, {
    cwd = wt_path,
    on_stdout = function(_, data, _)
      if not data or #data == 0 then
        return
      end
      data[1] = buffer .. data[1]
      for i = 1, #data - 1 do
        local line = data[i]
        if line and line ~= "" then
          local event = M.parse_stream_event(line)
          if event then
            handle_event(issue_number, event)
          end
        end
      end
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
        -- Handle any non-terminal status (running, initializing, etc.)
        if session.status ~= "completed" and session.status ~= "failed" then
          session.status = (exit_code == 0) and "completed" or "failed"
          utils.notify(string.format("Claude finished #%d (%s, exit %d)", issue_number, session.status, exit_code))
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

  session.job_id = job_id
  stop("Claude started on #" .. issue_number)
  callback(true, nil)
end
function M._launch_tmux(issue_number, headless_cmd, wt_path, stop, callback)
  local tmux = require("okuban.tmux")
  if not tmux.is_available() then
    active_sessions[issue_number] = nil
    stop("tmux not available — not inside a tmux session")
    callback(false, "tmux not available")
    return
  end

  local prompt = headless_cmd[3]
  local tmux_cmd = M.build_command(prompt, issue_number, { stream_json = false })
  local split_cfg = config.get().claude.tmux_split or {}
  local sentinel, pane_id, pane_err = tmux.launch_pane({
    name = "claude-#" .. issue_number,
    cwd = wt_path,
    cmd = tmux_cmd,
    env = M.build_env(),
    issue_number = issue_number,
    direction = split_cfg.direction,
    size = split_cfg.size,
    target = split_cfg.target,
  })
  if not sentinel then
    active_sessions[issue_number] = nil
    stop(pane_err or "Failed to launch tmux pane")
    callback(false, pane_err or "Failed to launch tmux pane")
    return
  end
  active_sessions[issue_number] = {
    job_id = nil,
    session_id = nil,
    worktree_path = wt_path,
    status = "running",
    turns = 0,
    cost_usd = nil,
    num_turns = nil,
    started_at = os.time(),
    sentinel_path = sentinel,
    pane_id = pane_id,
  }

  tmux.poll_sentinel(sentinel, 2000, function(exit_code)
    local session = active_sessions[issue_number]
    if session then
      session.status = (exit_code == 0) and "completed" or "failed"
      utils.notify(string.format("Claude finished #%d (%s, exit %d)", issue_number, session.status, exit_code))
    end
  end)

  stop("Claude started in tmux for #" .. issue_number)
  callback(true, nil)
end
function M.build_env()
  local cfg = config.get().claude
  local env = {}
  if cfg.agent_teams and cfg.agent_teams.enabled then
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
  end
  return env
end
function M.get_session(issue_number)
  return active_sessions[issue_number]
end
function M.get_all_sessions()
  return active_sessions
end
function M.build_resume_command(session_id, opts)
  opts = opts or {}
  local cmd = { "claude", "--resume", session_id }
  if opts.stream_json ~= false then
    table.insert(cmd, "--output-format")
    table.insert(cmd, "stream-json")
  end
  return cmd
end
function M.resume(issue, callback)
  callback = callback or function() end
  local issue_number = issue.number
  local session = active_sessions[issue_number]
  if not session or not session.session_id then
    callback(false, "No session to resume for #" .. issue_number)
    return
  end
  if session.status == "running" or session.status == "initializing" then
    callback(false, "Session is still running for #" .. issue_number)
    return
  end
  local wt_path = session.worktree_path
  if not wt_path then
    callback(false, "No worktree path for session #" .. issue_number)
    return
  end

  local mode = config.get().claude.launch_mode
  local is_tmux = mode == "tmux" or (mode == "auto" and require("okuban.tmux").is_available())
  local cmd = M.build_resume_command(session.session_id, { stream_json = not is_tmux })
  local noop_stop = function(msg)
    if msg then
      utils.notify(msg)
    end
  end
  M._launch_headless(issue_number, cmd, wt_path, noop_stop, callback)
end
--- Check all headless sessions for liveness and correct stale "running" status.
--- Uses vim.fn.jobwait() with 0 timeout (non-blocking) to detect dead jobs.
function M.verify_sessions()
  for _, session in pairs(active_sessions) do
    if session.status == "running" and session.job_id then
      local result = vim.fn.jobwait({ session.job_id }, 0)
      if result[1] ~= -1 then
        -- Job has exited but on_exit didn't update status (or was missed)
        session.status = "failed"
      end
    end
  end
end
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

local M = {}

--- Check if we're inside a tmux session.
---@return boolean
function M.is_available()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

--- Build the tmux command to launch a process in a new window.
--- The command is wrapped with a sentinel file that captures the exit code.
---@param opts { name: string, cwd: string, cmd: string[], env: table<string,string>|nil }
---@return string[] tmux_cmd, string sentinel_path
function M.build_launch_command(opts)
  local sentinel = vim.fn.tempname() .. ".okuban-sentinel"
  local script = M.write_launcher_script(opts.cmd, sentinel)
  local tmux_cmd = { "tmux", "new-window", "-n", opts.name, "-c", opts.cwd }
  if opts.env then
    for k, v in pairs(opts.env) do
      table.insert(tmux_cmd, "-e")
      table.insert(tmux_cmd, k .. "=" .. v)
    end
  end
  table.insert(tmux_cmd, script)
  return tmux_cmd, sentinel
end

--- Launch a command in a new tmux window.
---@param opts { name: string, cwd: string, cmd: string[], env: table<string,string>|nil }
---@return string|nil sentinel_path
function M.launch_window(opts)
  local tmux_cmd, sentinel = M.build_launch_command(opts)

  local result = vim.system(tmux_cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return sentinel
end

--- Poll a sentinel file for completion.
---@param sentinel string Path to sentinel file
---@param interval integer Poll interval in ms
---@param callback fun(exit_code: integer)
---@return userdata timer The uv timer handle
function M.poll_sentinel(sentinel, interval, callback)
  local timer = vim.uv.new_timer()
  timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      local f = io.open(sentinel, "r")
      if f then
        local content = f:read("*a")
        f:close()
        os.remove(sentinel)
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        local code = tonumber(content:match("%d+")) or 1
        callback(code)
      end
    end)
  )
  return timer
end

---@class TmuxPaneInfo
---@field pane_id string
---@field command string
---@field active boolean
---@field width integer
---@field okuban_issue string

--- Get the pane ID of the current Neovim instance.
---@return string|nil pane_id
function M.get_nvim_pane()
  local pane = vim.env.TMUX_PANE
  if not pane or pane == "" then
    return nil
  end
  return pane
end

--- List all panes in the current tmux window.
---@return TmuxPaneInfo[]|nil panes, string|nil error
function M.list_panes()
  local fmt = "#{pane_id}\t#{pane_current_command}\t#{pane_active}\t#{pane_width}\t#{@okuban_issue}"
  local result = vim.system({ "tmux", "list-panes", "-F", fmt }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, "tmux list-panes failed: " .. (result.stderr or "")
  end
  local panes = {}
  for line in (result.stdout or ""):gmatch("[^\n]+") do
    local id, cmd, active, width, issue = line:match("^(%%?%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if id then
      table.insert(panes, {
        pane_id = id,
        command = cmd or "",
        active = active == "1",
        width = tonumber(width) or 0,
        okuban_issue = issue or "",
      })
    end
  end
  return panes, nil
end

--- Find the best pane to split for a new Claude session.
--- "auto": prefer widest non-Neovim pane, fallback to Neovim pane.
--- "self": always split the Neovim pane.
--- "other": prefer widest non-Neovim pane, fallback to Neovim pane.
---@param panes TmuxPaneInfo[]
---@param nvim_pane_id string
---@param target "auto"|"self"|"other"|nil
---@return string pane_id
function M.find_split_target(panes, nvim_pane_id, target)
  target = target or "auto"
  if target == "self" then
    return nvim_pane_id
  end
  -- Find widest non-Neovim pane
  local best, best_width = nil, -1
  for _, p in ipairs(panes) do
    if p.pane_id ~= nvim_pane_id and p.width > best_width then
      best = p.pane_id
      best_width = p.width
    end
  end
  return best or nvim_pane_id
end

--- Check if a pane already exists for a given issue number.
---@param panes TmuxPaneInfo[]
---@param issue_number integer
---@return string|nil pane_id
function M.find_existing_pane(panes, issue_number)
  local tag = tostring(issue_number)
  for _, p in ipairs(panes) do
    if p.okuban_issue == tag then
      return p.pane_id
    end
  end
  return nil
end

--- Tag a pane with an issue number using a custom tmux option.
---@param pane_id string
---@param issue_number integer
---@return boolean ok
function M.tag_pane(pane_id, issue_number)
  local result = vim
    .system({ "tmux", "set-option", "-p", "-t", pane_id, "@okuban_issue", tostring(issue_number) }, { text = true })
    :wait()
  return result.code == 0
end

--- Write a launcher script that runs the command and writes exit code to sentinel.
--- Using a script file avoids shell quoting issues when passing complex args through tmux.
---@param cmd string[] Command to run
---@param sentinel string Path to sentinel file
---@return string script_path
function M.write_launcher_script(cmd, sentinel)
  local script = vim.fn.tempname() .. ".okuban-launcher.sh"
  local lines = { "#!/bin/sh" }
  -- Build the command with proper quoting
  local parts = {}
  for _, arg in ipairs(cmd) do
    table.insert(parts, vim.fn.shellescape(arg))
  end
  table.insert(lines, table.concat(parts, " "))
  table.insert(lines, string.format("echo $? > %s", vim.fn.shellescape(sentinel)))
  -- Clean up the script itself
  table.insert(lines, string.format("rm -f %s", vim.fn.shellescape(script)))
  local f = io.open(script, "w")
  if not f then
    return script
  end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
  vim.fn.setfperm(script, "rwx------")
  return script
end

--- Write prompt text to a temp file for safe passing to Claude via tmux.
--- This avoids all shell quoting issues with complex multi-line prompts.
---@param text string Prompt text
---@return string path Temp file path
function M.write_prompt_file(text)
  local path = vim.fn.tempname() .. ".okuban-prompt"
  local f = io.open(path, "w")
  if f then
    f:write(text)
    f:close()
  end
  return path
end

--- Write an interactive launcher script that reads prompt from file and runs Claude.
--- The prompt is read from a file to avoid shell quoting issues. Claude runs interactively
--- (no -p flag) so the user can see it working and follow up.
---@param cmd string[] Command flags (e.g., {"claude", "--max-turns", "10"})
---@param prompt_file string Path to file containing the prompt text
---@param sentinel string Path to sentinel file for exit code
---@return string script_path
function M.write_interactive_launcher(cmd, prompt_file, sentinel)
  local script = vim.fn.tempname() .. ".okuban-launcher.sh"
  local lines = { "#!/bin/sh" }
  -- Read prompt from file (avoids all shell quoting issues)
  table.insert(lines, string.format("PROMPT=$(cat %s)", vim.fn.shellescape(prompt_file)))
  table.insert(lines, string.format("rm -f %s", vim.fn.shellescape(prompt_file)))
  -- Build command: claude "$PROMPT" [flags...]
  local parts = { vim.fn.shellescape(cmd[1]), '"$PROMPT"' }
  for i = 2, #cmd do
    table.insert(parts, vim.fn.shellescape(cmd[i]))
  end
  table.insert(lines, table.concat(parts, " "))
  -- Write exit code to sentinel
  table.insert(lines, string.format("echo $? > %s", vim.fn.shellescape(sentinel)))
  -- Clean up script
  table.insert(lines, string.format("rm -f %s", vim.fn.shellescape(script)))
  local f = io.open(script, "w")
  if not f then
    return script
  end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
  vim.fn.setfperm(script, "rwx------")
  return script
end

--- Build a tmux split-window command with sentinel wrapper.
---@param opts table Split options: target, cwd, cmd, env, direction, size, prompt_file
---@return string[] tmux_cmd, string sentinel_path
function M.build_split_command(opts)
  local sentinel = vim.fn.tempname() .. ".okuban-sentinel"
  local script
  if opts.prompt_file then
    script = M.write_interactive_launcher(opts.cmd, opts.prompt_file, sentinel)
  else
    script = M.write_launcher_script(opts.cmd, sentinel)
  end
  local direction = opts.direction or "h"
  local tmux_cmd = { "tmux", "split-window", "-" .. direction, "-d", "-P", "-F", "#{pane_id}", "-t", opts.target }
  if opts.size then
    table.insert(tmux_cmd, "-l")
    table.insert(tmux_cmd, opts.size)
  end
  table.insert(tmux_cmd, "-c")
  table.insert(tmux_cmd, opts.cwd)
  if opts.env then
    for k, v in pairs(opts.env) do
      table.insert(tmux_cmd, "-e")
      table.insert(tmux_cmd, k .. "=" .. v)
    end
  end
  table.insert(tmux_cmd, script)
  return tmux_cmd, sentinel
end

--- Launch a command in a new tmux pane by splitting an existing one.
---@param opts table Pane opts: name, cwd, cmd, env, issue_number, direction, size, target, prompt_file
---@return string|nil sentinel_path, string|nil pane_id, string|nil error
function M.launch_pane(opts)
  local nvim_pane = M.get_nvim_pane()
  if not nvim_pane then
    return nil, nil, "TMUX_PANE not set — cannot determine Neovim pane"
  end
  local panes, list_err = M.list_panes()
  if not panes then
    return nil, nil, list_err or "Failed to list tmux panes"
  end
  local existing = M.find_existing_pane(panes, opts.issue_number)
  if existing then
    return nil, nil, "Pane already exists for #" .. opts.issue_number
  end
  local split_target = M.find_split_target(panes, nvim_pane, opts.target)
  local tmux_cmd, sentinel = M.build_split_command({
    target = split_target,
    cwd = opts.cwd,
    cmd = opts.cmd,
    prompt_file = opts.prompt_file,
    env = opts.env,
    direction = opts.direction,
    size = opts.size,
  })
  local result = vim.system(tmux_cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil, nil, "tmux split-window failed: " .. (result.stderr or "")
  end
  local new_pane_id = vim.trim(result.stdout or "")
  if new_pane_id ~= "" then
    M.tag_pane(new_pane_id, opts.issue_number)
  end
  return sentinel, new_pane_id, nil
end

return M

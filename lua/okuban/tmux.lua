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
  -- Build the inner command string (shell-escaped)
  local parts = {}
  for _, arg in ipairs(opts.cmd) do
    table.insert(parts, vim.fn.shellescape(arg))
  end
  local inner = table.concat(parts, " ")

  -- Sentinel file for completion detection
  local sentinel = vim.fn.tempname() .. ".okuban-sentinel"

  -- Wrapper: run command, capture exit code, write to sentinel
  local wrapper = string.format("%s; echo $? > %s", inner, vim.fn.shellescape(sentinel))

  -- Build tmux command
  local tmux_cmd = { "tmux", "new-window", "-n", opts.name, "-c", opts.cwd }

  -- Add environment variables
  if opts.env then
    for k, v in pairs(opts.env) do
      table.insert(tmux_cmd, "-e")
      table.insert(tmux_cmd, k .. "=" .. v)
    end
  end

  table.insert(tmux_cmd, wrapper)

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

return M

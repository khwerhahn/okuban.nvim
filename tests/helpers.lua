local M = {}

local original_vim_system = vim.system

--- Mock vim.system() with predefined responses.
--- Responses are matched in order. Each call consumes the next response.
---@param responses table[] List of { code, stdout, stderr } tables
function M.mock_vim_system(responses)
  local call_idx = 0
  local calls = {}

  vim.system = function(cmd, opts, on_exit)
    call_idx = call_idx + 1
    table.insert(calls, { cmd = cmd, opts = opts })
    local resp = responses[call_idx] or { code = 1, stdout = "", stderr = "unexpected call #" .. call_idx }

    local result = {
      code = resp.code or 0,
      stdout = resp.stdout or "",
      stderr = resp.stderr or "",
    }

    if on_exit then
      vim.schedule(function()
        on_exit(result)
      end)
    end

    return {
      wait = function()
        return result
      end,
    }
  end

  return calls
end

--- Restore the original vim.system().
function M.restore_vim_system()
  vim.system = original_vim_system
end

return M

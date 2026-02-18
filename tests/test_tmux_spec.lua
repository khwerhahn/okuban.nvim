describe("okuban.tmux", function()
  local tmux

  before_each(function()
    package.loaded["okuban.tmux"] = nil
    tmux = require("okuban.tmux")
  end)

  describe("is_available", function()
    it("returns true when TMUX env is set", function()
      local orig = vim.env.TMUX
      vim.env.TMUX = "/tmp/tmux-1000/default,12345,0"
      assert.is_true(tmux.is_available())
      vim.env.TMUX = orig
    end)

    it("returns false when TMUX env is nil", function()
      local orig = vim.env.TMUX
      vim.env.TMUX = nil
      assert.is_false(tmux.is_available())
      vim.env.TMUX = orig
    end)

    it("returns false when TMUX env is empty", function()
      local orig = vim.env.TMUX
      vim.env.TMUX = ""
      assert.is_false(tmux.is_available())
      vim.env.TMUX = orig
    end)
  end)

  describe("build_launch_command", function()
    it("builds tmux new-window command with correct structure", function()
      local cmd, sentinel = tmux.build_launch_command({
        name = "test-win",
        cwd = "/tmp/work",
        cmd = { "echo", "hello" },
      })
      assert.are.equal("tmux", cmd[1])
      assert.are.equal("new-window", cmd[2])
      assert.are.equal("-n", cmd[3])
      assert.are.equal("test-win", cmd[4])
      assert.are.equal("-c", cmd[5])
      assert.are.equal("/tmp/work", cmd[6])
      assert.is_truthy(sentinel:find("okuban%-sentinel"))
    end)

    it("includes environment variables", function()
      local cmd, _ = tmux.build_launch_command({
        name = "test",
        cwd = "/tmp",
        cmd = { "echo" },
        env = { FOO = "bar", BAZ = "qux" },
      })
      local found_env = false
      for i, v in ipairs(cmd) do
        if v == "-e" and cmd[i + 1] then
          found_env = true
        end
      end
      assert.is_true(found_env, "expected -e flags for environment variables")
    end)

    it("returns a sentinel path as second return value", function()
      local _, sentinel = tmux.build_launch_command({
        name = "test",
        cwd = "/tmp",
        cmd = { "echo" },
      })
      assert.is_truthy(sentinel)
      assert.is_truthy(sentinel:match("%.okuban%-sentinel$"))
    end)

    it("wraps command with sentinel write", function()
      local cmd = tmux.build_launch_command({
        name = "test",
        cwd = "/tmp",
        cmd = { "claude", "-p", "hello world" },
      })
      -- Last element should be the wrapper command
      local wrapper = cmd[#cmd]
      assert.is_truthy(wrapper:find("echo %$%?"))
      assert.is_truthy(wrapper:find("claude"))
    end)
  end)

  describe("poll_sentinel", function()
    it("calls callback when sentinel file exists", function()
      -- Create a sentinel file
      local sentinel = vim.fn.tempname() .. ".okuban-sentinel"
      local f = io.open(sentinel, "w")
      f:write("0\n")
      f:close()

      local done = false
      local result_code
      tmux.poll_sentinel(sentinel, 100, function(exit_code)
        result_code = exit_code
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)
      assert.is_true(done)
      assert.are.equal(0, result_code)
      -- Sentinel should be cleaned up
      assert.is_nil(io.open(sentinel, "r"))
    end)

    it("returns non-zero exit code from sentinel", function()
      local sentinel = vim.fn.tempname() .. ".okuban-sentinel"
      local f = io.open(sentinel, "w")
      f:write("1\n")
      f:close()

      local done = false
      local result_code
      tmux.poll_sentinel(sentinel, 100, function(exit_code)
        result_code = exit_code
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)
      assert.is_true(done)
      assert.are.equal(1, result_code)
    end)

    it("returns timer handle", function()
      local sentinel = vim.fn.tempname() .. ".okuban-sentinel-never"
      local timer = tmux.poll_sentinel(sentinel, 5000, function() end)
      assert.is_not_nil(timer)
      -- Clean up
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
    end)
  end)
end)

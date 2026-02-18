describe("okuban.tmux", function()
  local tmux
  local helpers = require("tests.helpers")

  before_each(function()
    package.loaded["okuban.tmux"] = nil
    tmux = require("okuban.tmux")
  end)

  after_each(function()
    helpers.restore_vim_system()
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

    it("uses launcher script with sentinel write", function()
      local cmd = tmux.build_launch_command({
        name = "test",
        cwd = "/tmp",
        cmd = { "claude", "-p", "hello world" },
      })
      -- Last element should be the script path
      local script_path = cmd[#cmd]
      assert.is_truthy(script_path:find("okuban%-launcher%.sh"))
      -- Script content should have the command and sentinel write
      local f = io.open(script_path, "r")
      assert.is_truthy(f)
      local content = f:read("*a")
      f:close()
      os.remove(script_path)
      assert.is_truthy(content:find("claude"))
      assert.is_truthy(content:find("echo %$%?"))
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

  describe("get_nvim_pane", function()
    it("returns TMUX_PANE when set", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = "%42"
      assert.are.equal("%42", tmux.get_nvim_pane())
      vim.env.TMUX_PANE = orig
    end)

    it("returns nil when TMUX_PANE is nil", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = nil
      assert.is_nil(tmux.get_nvim_pane())
      vim.env.TMUX_PANE = orig
    end)

    it("returns nil when TMUX_PANE is empty", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = ""
      assert.is_nil(tmux.get_nvim_pane())
      vim.env.TMUX_PANE = orig
    end)
  end)

  describe("list_panes", function()
    it("parses multi-pane output", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "%0\tnvim\t1\t120\t\n%1\tbash\t0\t80\t42\n" },
      })
      local panes, err = tmux.list_panes()
      assert.is_nil(err)
      assert.are.equal(2, #panes)
      assert.are.equal("%0", panes[1].pane_id)
      assert.are.equal("nvim", panes[1].command)
      assert.is_true(panes[1].active)
      assert.are.equal(120, panes[1].width)
      assert.are.equal("", panes[1].okuban_issue)
      assert.are.equal("%1", panes[2].pane_id)
      assert.are.equal("bash", panes[2].command)
      assert.is_false(panes[2].active)
      assert.are.equal(80, panes[2].width)
      assert.are.equal("42", panes[2].okuban_issue)
    end)

    it("parses pane with custom okuban_issue option", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "%5\tclaude\t0\t60\t99\n" },
      })
      local panes = tmux.list_panes()
      assert.are.equal(1, #panes)
      assert.are.equal("99", panes[1].okuban_issue)
    end)

    it("returns error when tmux command fails", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "server not found" },
      })
      local panes, err = tmux.list_panes()
      assert.is_nil(panes)
      assert.is_truthy(err:find("list%-panes failed"))
    end)

    it("handles single pane output", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "%0\tnvim\t1\t200\t\n" },
      })
      local panes = tmux.list_panes()
      assert.are.equal(1, #panes)
      assert.are.equal("%0", panes[1].pane_id)
    end)
  end)

  describe("find_split_target", function()
    local panes = {
      { pane_id = "%0", command = "nvim", active = true, width = 120, okuban_issue = "" },
      { pane_id = "%1", command = "bash", active = false, width = 80, okuban_issue = "" },
      { pane_id = "%2", command = "zsh", active = false, width = 100, okuban_issue = "" },
    }

    it("prefers widest non-nvim pane in auto mode", function()
      local target = tmux.find_split_target(panes, "%0", "auto")
      assert.are.equal("%2", target)
    end)

    it("prefers widest non-nvim pane in other mode", function()
      local target = tmux.find_split_target(panes, "%0", "other")
      assert.are.equal("%2", target)
    end)

    it("returns nvim pane in self mode", function()
      local target = tmux.find_split_target(panes, "%0", "self")
      assert.are.equal("%0", target)
    end)

    it("falls back to nvim pane when it is the only pane", function()
      local single = {
        { pane_id = "%0", command = "nvim", active = true, width = 200, okuban_issue = "" },
      }
      local target = tmux.find_split_target(single, "%0", "auto")
      assert.are.equal("%0", target)
    end)
  end)

  describe("find_existing_pane", function()
    it("returns pane_id when issue tag matches", function()
      local panes = {
        { pane_id = "%0", okuban_issue = "" },
        { pane_id = "%1", okuban_issue = "42" },
      }
      assert.are.equal("%1", tmux.find_existing_pane(panes, 42))
    end)

    it("returns nil when no pane matches", function()
      local panes = {
        { pane_id = "%0", okuban_issue = "" },
        { pane_id = "%1", okuban_issue = "99" },
      }
      assert.is_nil(tmux.find_existing_pane(panes, 42))
    end)

    it("returns nil for empty pane list", function()
      assert.is_nil(tmux.find_existing_pane({}, 42))
    end)
  end)

  describe("tag_pane", function()
    it("returns true on success", function()
      local calls = helpers.mock_vim_system({
        { code = 0 },
      })
      assert.is_true(tmux.tag_pane("%5", 42))
      assert.are.equal("tmux", calls[1].cmd[1])
      assert.are.equal("set-option", calls[1].cmd[2])
      assert.are.equal("-p", calls[1].cmd[3])
      assert.are.equal("-t", calls[1].cmd[4])
      assert.are.equal("%5", calls[1].cmd[5])
      assert.are.equal("@okuban_issue", calls[1].cmd[6])
      assert.are.equal("42", calls[1].cmd[7])
    end)

    it("returns false on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "no such pane" },
      })
      assert.is_false(tmux.tag_pane("%99", 42))
    end)
  end)

  describe("write_launcher_script", function()
    it("creates executable script with command and sentinel", function()
      local sentinel = "/tmp/test-sentinel"
      local script = tmux.write_launcher_script({ "echo", "hello world" }, sentinel)
      assert.is_truthy(script:find("okuban%-launcher%.sh"))
      local f = io.open(script, "r")
      assert.is_truthy(f)
      local content = f:read("*a")
      f:close()
      os.remove(script)
      assert.is_truthy(content:find("#!/bin/sh"))
      assert.is_truthy(content:find("echo"))
      assert.is_truthy(content:find("hello world"))
      assert.is_truthy(content:find("echo %$%?"))
      assert.is_truthy(content:find(sentinel))
    end)

    it("cleans up the script file after execution", function()
      local sentinel = "/tmp/test-sentinel"
      local script = tmux.write_launcher_script({ "echo" }, sentinel)
      local f = io.open(script, "r")
      local content = f:read("*a")
      f:close()
      os.remove(script)
      assert.is_truthy(content:find("rm %-f"))
    end)
  end)

  describe("build_split_command", function()
    it("builds split-window command with correct structure", function()
      local cmd, sentinel = tmux.build_split_command({
        target = "%0",
        cwd = "/tmp/work",
        cmd = { "echo", "hello" },
      })
      assert.are.equal("tmux", cmd[1])
      assert.are.equal("split-window", cmd[2])
      assert.are.equal("-h", cmd[3])
      assert.are.equal("-d", cmd[4])
      assert.are.equal("-P", cmd[5])
      assert.are.equal("-F", cmd[6])
      assert.are.equal("#{pane_id}", cmd[7])
      assert.are.equal("-t", cmd[8])
      assert.are.equal("%0", cmd[9])
      assert.is_truthy(sentinel:find("okuban%-sentinel"))
    end)

    it("uses specified target pane", function()
      local cmd = tmux.build_split_command({
        target = "%5",
        cwd = "/tmp",
        cmd = { "echo" },
      })
      assert.are.equal("%5", cmd[9])
    end)

    it("includes size when specified", function()
      local cmd = tmux.build_split_command({
        target = "%0",
        cwd = "/tmp",
        cmd = { "echo" },
        size = "50%",
      })
      local found_size = false
      for i, v in ipairs(cmd) do
        if v == "-l" and cmd[i + 1] == "50%" then
          found_size = true
        end
      end
      assert.is_true(found_size, "expected -l 50% in command")
    end)

    it("includes environment variables", function()
      local cmd = tmux.build_split_command({
        target = "%0",
        cwd = "/tmp",
        cmd = { "echo" },
        env = { FOO = "bar" },
      })
      local found_env = false
      for i, v in ipairs(cmd) do
        if v == "-e" and cmd[i + 1] and cmd[i + 1]:find("FOO=bar") then
          found_env = true
        end
      end
      assert.is_true(found_env, "expected -e FOO=bar in command")
    end)
  end)

  describe("launch_pane", function()
    it("orchestrates full flow successfully", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = "%0"
      helpers.mock_vim_system({
        -- list_panes
        { code = 0, stdout = "%0\tnvim\t1\t120\t\n%1\tbash\t0\t80\t\n" },
        -- split-window
        { code = 0, stdout = "%3\n" },
        -- tag_pane
        { code = 0 },
      })
      local sentinel, pane_id, err = tmux.launch_pane({
        name = "claude-#42",
        cwd = "/tmp/work",
        cmd = { "claude", "-p", "test" },
        issue_number = 42,
      })
      assert.is_truthy(sentinel)
      assert.are.equal("%3", pane_id)
      assert.is_nil(err)
      vim.env.TMUX_PANE = orig
    end)

    it("returns error when pane already exists for issue", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = "%0"
      helpers.mock_vim_system({
        -- list_panes: pane %1 already tagged with issue 42
        { code = 0, stdout = "%0\tnvim\t1\t120\t\n%1\tclaude\t0\t80\t42\n" },
      })
      local sentinel, pane_id, err = tmux.launch_pane({
        name = "claude-#42",
        cwd = "/tmp/work",
        cmd = { "claude" },
        issue_number = 42,
      })
      assert.is_nil(sentinel)
      assert.is_nil(pane_id)
      assert.is_truthy(err:find("already exists"))
      vim.env.TMUX_PANE = orig
    end)

    it("returns error when TMUX_PANE is not set", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = nil
      local sentinel, pane_id, err = tmux.launch_pane({
        name = "claude-#42",
        cwd = "/tmp/work",
        cmd = { "claude" },
        issue_number = 42,
      })
      assert.is_nil(sentinel)
      assert.is_nil(pane_id)
      assert.is_truthy(err:find("TMUX_PANE"))
      vim.env.TMUX_PANE = orig
    end)

    it("returns error when list-panes fails", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = "%0"
      helpers.mock_vim_system({
        { code = 1, stderr = "server exited" },
      })
      local sentinel, pane_id, err = tmux.launch_pane({
        name = "claude-#42",
        cwd = "/tmp/work",
        cmd = { "claude" },
        issue_number = 42,
      })
      assert.is_nil(sentinel)
      assert.is_nil(pane_id)
      assert.is_truthy(err:find("list%-panes"))
      vim.env.TMUX_PANE = orig
    end)

    it("returns error when split-window fails", function()
      local orig = vim.env.TMUX_PANE
      vim.env.TMUX_PANE = "%0"
      helpers.mock_vim_system({
        -- list_panes
        { code = 0, stdout = "%0\tnvim\t1\t120\t\n" },
        -- split-window fails (pane too small)
        { code = 1, stderr = "pane too small" },
      })
      local sentinel, pane_id, err = tmux.launch_pane({
        name = "claude-#42",
        cwd = "/tmp/work",
        cmd = { "claude" },
        issue_number = 42,
      })
      assert.is_nil(sentinel)
      assert.is_nil(pane_id)
      assert.is_truthy(err:find("split%-window failed"))
      vim.env.TMUX_PANE = orig
    end)
  end)
end)

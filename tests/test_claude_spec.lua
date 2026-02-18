local helpers = require("tests.helpers")

describe("okuban.claude", function()
  local claude
  local config

  before_each(function()
    config = require("okuban.config")
    config.setup()
    claude = require("okuban.claude")
    claude._reset()
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("config defaults", function()
    it("has allowed_tools with expected entries", function()
      local cfg = config.get().claude
      assert.is_table(cfg.allowed_tools)
      assert.is_true(#cfg.allowed_tools > 0)
      assert.is_true(vim.tbl_contains(cfg.allowed_tools, "Read"))
      assert.is_true(vim.tbl_contains(cfg.allowed_tools, "Edit"))
      assert.is_true(vim.tbl_contains(cfg.allowed_tools, "Bash(git:*)"))
    end)

    it("has worktree_base_dir as nil by default", function()
      local cfg = config.get().claude
      assert.is_nil(cfg.worktree_base_dir)
    end)

    it("has auto_push and auto_pr as false by default", function()
      local cfg = config.get().claude
      assert.is_false(cfg.auto_push)
      assert.is_false(cfg.auto_pr)
    end)

    it("has max_budget_usd as 5.00 by default", function()
      local cfg = config.get().claude
      assert.are.equal(5.00, cfg.max_budget_usd)
    end)

    it("has model as nil by default", function()
      local cfg = config.get().claude
      assert.is_nil(cfg.model)
    end)

    it("allows overriding allowed_tools via setup", function()
      config.setup({ claude = { allowed_tools = { "Read", "Write" } } })
      local cfg = config.get().claude
      assert.are.equal(2, #cfg.allowed_tools)
      assert.are.equal("Read", cfg.allowed_tools[1])
    end)
  end)

  describe("is_available", function()
    it("returns true when claude executable exists", function()
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "claude" then
          return 1
        end
        return orig(name)
      end
      claude._reset()
      assert.is_true(claude.is_available())
      vim.fn.executable = orig
    end)

    it("returns false when claude executable is not found", function()
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "claude" then
          return 0
        end
        return orig(name)
      end
      claude._reset()
      assert.is_false(claude.is_available())
      vim.fn.executable = orig
    end)

    it("caches the result", function()
      local call_count = 0
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "claude" then
          call_count = call_count + 1
          return 1
        end
        return orig(name)
      end
      claude._reset()
      claude.is_available()
      claude.is_available()
      claude.is_available()
      assert.are.equal(1, call_count)
      vim.fn.executable = orig
    end)
  end)

  describe("worktree_path", function()
    it("computes path using repo root when no custom base dir", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "/home/user/myrepo\n" },
      })
      local path, err = claude.worktree_path(42)
      assert.is_nil(err)
      assert.are.equal("/home/user/myrepo-worktrees/issue-42", path)
    end)

    it("uses custom worktree_base_dir when configured", function()
      config.setup({ claude = { worktree_base_dir = "/tmp/worktrees" } })
      local path, err = claude.worktree_path(99)
      assert.is_nil(err)
      assert.are.equal("/tmp/worktrees/issue-99", path)
    end)

    it("returns error when git repo root cannot be determined", function()
      helpers.mock_vim_system({
        { code = 128, stdout = "", stderr = "not a git repo" },
      })
      local path, err = claude.worktree_path(1)
      assert.is_nil(path)
      assert.is_not_nil(err)
    end)
  end)

  describe("parse_stream_event", function()
    it("parses system init event", function()
      local line = vim.json.encode({ type = "system", subtype = "init", session_id = "abc-123" })
      local event = claude.parse_stream_event(line)
      assert.is_not_nil(event)
      assert.are.equal("system", event.type)
      assert.are.equal("init", event.subtype)
      assert.are.equal("abc-123", event.session_id)
    end)

    it("parses assistant event", function()
      local line = vim.json.encode({ type = "assistant", message = { content = "working..." } })
      local event = claude.parse_stream_event(line)
      assert.is_not_nil(event)
      assert.are.equal("assistant", event.type)
    end)

    it("parses result event with success", function()
      local line = vim.json.encode({
        type = "result",
        is_error = false,
        total_cost_usd = 1.23,
        num_turns = 5,
      })
      local event = claude.parse_stream_event(line)
      assert.is_not_nil(event)
      assert.are.equal("result", event.type)
      assert.is_false(event.is_error)
      assert.are.equal(1.23, event.total_cost_usd)
      assert.are.equal(5, event.num_turns)
    end)

    it("parses result event with error", function()
      local line = vim.json.encode({
        type = "result",
        is_error = true,
        total_cost_usd = 0.50,
        num_turns = 2,
      })
      local event = claude.parse_stream_event(line)
      assert.is_not_nil(event)
      assert.is_true(event.is_error)
    end)

    it("returns nil for invalid JSON", function()
      assert.is_nil(claude.parse_stream_event("not json"))
    end)

    it("returns nil for empty string", function()
      assert.is_nil(claude.parse_stream_event(""))
    end)

    it("returns nil for nil input", function()
      assert.is_nil(claude.parse_stream_event(nil))
    end)
  end)

  describe("build_command", function()
    --- Helper to find a flag and its value in a command table.
    local function find_flag(cmd, flag, expected_value)
      for i, v in ipairs(cmd) do
        if v == flag then
          if expected_value == nil then
            return true
          end
          return cmd[i + 1] == expected_value
        end
      end
      return false
    end

    it("includes -p flag with prompt", function()
      local cmd = claude.build_command("test prompt", 42)
      assert.are.equal("claude", cmd[1])
      assert.are.equal("-p", cmd[2])
      assert.are.equal("test prompt", cmd[3])
    end)

    it("includes --output-format stream-json", function()
      local cmd = claude.build_command("prompt", 42)
      assert.is_true(find_flag(cmd, "--output-format", "stream-json"), "expected --output-format stream-json")
    end)

    it("includes --dangerously-skip-permissions", function()
      local cmd = claude.build_command("prompt", 42)
      assert.is_true(find_flag(cmd, "--dangerously-skip-permissions"), "expected --dangerously-skip-permissions")
    end)

    it("includes --max-turns from config", function()
      local cmd = claude.build_command("prompt", 42)
      assert.is_true(find_flag(cmd, "--max-turns", "30"), "expected --max-turns 30")
    end)

    it("includes --max-budget-usd from config", function()
      local cmd = claude.build_command("prompt", 42)
      assert.is_true(find_flag(cmd, "--max-budget-usd", "5"), "expected --max-budget-usd 5")
    end)

    it("includes --append-system-prompt with issue reference", function()
      local cmd = claude.build_command("prompt", 42)
      local found = false
      for i, v in ipairs(cmd) do
        if v == "--append-system-prompt" and cmd[i + 1] and cmd[i + 1]:find("Fixes #42") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected --append-system-prompt with Fixes #42")
    end)

    it("includes --allowedTools for each configured tool", function()
      local cmd = claude.build_command("prompt", 42)
      local tool_count = 0
      for _, v in ipairs(cmd) do
        if v == "--allowedTools" then
          tool_count = tool_count + 1
        end
      end
      local cfg = config.get().claude
      assert.are.equal(#cfg.allowed_tools, tool_count)
    end)

    it("respects custom max_budget_usd", function()
      config.setup({ claude = { max_budget_usd = 10.50 } })
      local cmd = claude.build_command("prompt", 42)
      assert.is_true(find_flag(cmd, "--max-budget-usd", "10.5"), "expected --max-budget-usd 10.5")
    end)

    it("includes --model when configured", function()
      config.setup({ claude = { model = "sonnet" } })
      local cmd = claude.build_command("prompt", 42)
      assert.is_true(find_flag(cmd, "--model", "sonnet"), "expected --model sonnet")
    end)

    it("omits --model when not configured", function()
      local cmd = claude.build_command("prompt", 42)
      assert.is_false(find_flag(cmd, "--model"), "expected no --model flag")
    end)
  end)

  describe("build_prompt", function()
    it("includes issue number in prompt", function()
      local prompt = claude.build_prompt(42, { title = "Fix bug", body = "" })
      assert.is_truthy(prompt:find("#42"))
    end)

    it("includes issue title", function()
      local prompt = claude.build_prompt(1, { title = "Add dark mode" })
      assert.is_truthy(prompt:find("Add dark mode"))
    end)

    it("includes issue body when present", function()
      local prompt = claude.build_prompt(1, { title = "T", body = "Detailed description here" })
      assert.is_truthy(prompt:find("Detailed description here"))
    end)

    it("includes label names when present", function()
      local prompt = claude.build_prompt(1, {
        title = "T",
        labels = { { name = "type: bug" }, { name = "priority: high" } },
      })
      assert.is_truthy(prompt:find("type: bug"))
      assert.is_truthy(prompt:find("priority: high"))
    end)

    it("includes recent comments", function()
      local prompt = claude.build_prompt(1, {
        title = "T",
        comments = { { body = "First comment" }, { body = "Second comment" } },
      })
      assert.is_truthy(prompt:find("First comment"))
      assert.is_truthy(prompt:find("Second comment"))
    end)

    it("limits to last 5 comments", function()
      local comments = {}
      for i = 1, 8 do
        table.insert(comments, { body = "Comment " .. i })
      end
      local prompt = claude.build_prompt(1, { title = "T", comments = comments })
      -- Should include comments 4-8 (last 5)
      assert.is_falsy(prompt:find("Comment 3\n"))
      assert.is_truthy(prompt:find("Comment 4"))
      assert.is_truthy(prompt:find("Comment 8"))
    end)

    it("does not include commit instructions (moved to system prompt)", function()
      local prompt = claude.build_prompt(42, { title = "T" })
      assert.is_falsy(prompt:find("commit"))
    end)
  end)

  describe("build_system_prompt", function()
    it("includes Fixes reference for issue number", function()
      local sp = claude.build_system_prompt(42)
      assert.is_truthy(sp:find("Fixes #42"))
    end)

    it("includes Refs reference for issue number", function()
      local sp = claude.build_system_prompt(42)
      assert.is_truthy(sp:find("Refs #42"))
    end)

    it("mentions CLAUDE.md conventions", function()
      local sp = claude.build_system_prompt(1)
      assert.is_truthy(sp:find("CLAUDE.md"))
    end)
  end)

  describe("session state", function()
    it("get_session returns nil when no session exists", function()
      assert.is_nil(claude.get_session(42))
    end)

    it("get_all_sessions returns empty table initially", function()
      local sessions = claude.get_all_sessions()
      assert.are.equal(0, vim.tbl_count(sessions))
    end)

    it("_reset clears all state", function()
      -- Manually inject a session for testing
      local sessions = claude.get_all_sessions()
      sessions[42] = { status = "running", job_id = 1 }
      assert.is_not_nil(claude.get_session(42))

      claude._reset()
      assert.is_nil(claude.get_session(42))
    end)
  end)

  describe("find_existing_worktree", function()
    it("returns path when worktree exists", function()
      config.setup({ claude = { worktree_base_dir = "/tmp/wt" } })
      helpers.mock_vim_system({
        { code = 0, stdout = "worktree /tmp/wt/issue-42\nHEAD abc123\nbranch refs/heads/feat\n\n" },
      })
      local path = claude.find_existing_worktree(42)
      assert.are.equal("/tmp/wt/issue-42", path)
    end)

    it("returns nil when worktree does not exist", function()
      config.setup({ claude = { worktree_base_dir = "/tmp/wt" } })
      helpers.mock_vim_system({
        { code = 0, stdout = "worktree /home/user/repo\nHEAD abc123\n\n" },
      })
      local path = claude.find_existing_worktree(42)
      assert.is_nil(path)
    end)
  end)

  describe("check_auth", function()
    it("invokes callback with true on success", function()
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "claude" then
          return 1
        end
        return orig(name)
      end
      claude._reset()

      helpers.mock_vim_system({
        { code = 0, stdout = "claude 1.0.0\n" },
      })

      local done = false
      local result_ok, result_err
      claude.check_auth(function(ok, err)
        result_ok = ok
        result_err = err
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_true(result_ok)
      assert.is_nil(result_err)
      vim.fn.executable = orig
    end)

    it("invokes callback with false when CLI not found", function()
      local orig = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "claude" then
          return 0
        end
        return orig(name)
      end
      claude._reset()

      local result_ok, result_err
      claude.check_auth(function(ok, err)
        result_ok = ok
        result_err = err
      end)

      assert.is_false(result_ok)
      assert.is_truthy(result_err)
      vim.fn.executable = orig
    end)
  end)

  describe("create_worktree", function()
    it("returns existing worktree without creating", function()
      config.setup({ claude = { worktree_base_dir = "/tmp/wt" } })
      helpers.mock_vim_system({
        -- find_existing_worktree: git worktree list
        { code = 0, stdout = "worktree /tmp/wt/issue-42\nHEAD abc\n\n" },
      })

      local result_ok, result_path
      claude.create_worktree(42, function(ok, path, _err)
        result_ok = ok
        result_path = path
      end)

      assert.is_true(result_ok)
      assert.are.equal("/tmp/wt/issue-42", result_path)
    end)

    it("creates new worktree on success", function()
      config.setup({ claude = { worktree_base_dir = "/tmp/wt" } })
      helpers.mock_vim_system({
        -- find_existing_worktree: git worktree list (empty)
        { code = 0, stdout = "worktree /home/user/repo\nHEAD abc\n\n" },
        -- git worktree add -b branch path
        { code = 0, stdout = "" },
      })

      local done = false
      local result_ok, result_path
      claude.create_worktree(42, function(ok, path, _err)
        result_ok = ok
        result_path = path
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_true(result_ok)
      assert.are.equal("/tmp/wt/issue-42", result_path)
    end)

    it("reports error when worktree creation fails", function()
      config.setup({ claude = { worktree_base_dir = "/tmp/wt" } })
      helpers.mock_vim_system({
        -- find_existing_worktree: git worktree list (empty)
        { code = 0, stdout = "worktree /home/user/repo\nHEAD abc\n\n" },
        -- git worktree add -b (fails)
        { code = 128, stdout = "", stderr = "branch exists" },
        -- git worktree add (fallback, also fails)
        { code = 128, stdout = "", stderr = "fatal error" },
      })

      local done = false
      local result_ok, result_err
      claude.create_worktree(42, function(ok, _path, err)
        result_ok = ok
        result_err = err
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_false(result_ok)
      assert.is_truthy(result_err)
    end)
  end)

  describe("fetch_issue_context", function()
    it("parses gh JSON on success", function()
      local json = vim.json.encode({
        number = 42,
        title = "Fix bug",
        body = "Description",
        labels = { { name = "type: bug" } },
        comments = {},
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result_ctx
      claude.fetch_issue_context(42, function(ctx, _err)
        result_ctx = ctx
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_not_nil(result_ctx)
      assert.are.equal("Fix bug", result_ctx.title)
      assert.are.equal(42, result_ctx.number)
    end)

    it("returns error on gh failure", function()
      helpers.mock_vim_system({
        { code = 1, stdout = "", stderr = "not found" },
      })

      local done = false
      local result_err
      claude.fetch_issue_context(999, function(_ctx, err)
        result_err = err
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_truthy(result_err)
    end)
  end)

  describe("stop", function()
    it("returns false when no session exists", function()
      assert.is_false(claude.stop(42))
    end)

    it("returns false when session is not running", function()
      local sessions = claude.get_all_sessions()
      sessions[42] = { status = "completed", job_id = 1 }
      assert.is_false(claude.stop(42))
    end)
  end)
end)

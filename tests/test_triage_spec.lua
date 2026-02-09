local helpers = require("tests.helpers")

describe("okuban.triage", function()
  local triage, config

  before_each(function()
    package.loaded["okuban.triage"] = nil
    package.loaded["okuban.config"] = nil
    package.loaded["okuban.api"] = nil
    config = require("okuban.config")
    config.setup()
    require("okuban.api")._reset_preflight()
    triage = require("okuban.triage")
    triage._reset()
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  -- -----------------------------------------------------------------------
  -- classify_issue
  -- -----------------------------------------------------------------------
  describe("classify_issue", function()
    local pattern_map

    before_each(function()
      pattern_map = triage._DEFAULT_PATTERN_MAP
    end)

    it("classifies closed issues as done", function()
      local issue = { number = 1, title = "Test", state = "CLOSED", labels = {} }
      local label, reason = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:done", label)
      assert.equals("closed", reason)
    end)

    it("classifies lowercase closed state as done", function()
      local issue = { number = 1, title = "Test", state = "closed", labels = {} }
      local label, reason = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:done", label)
      assert.equals("closed", reason)
    end)

    it("matches status:in-progress label", function()
      local issue = {
        number = 2,
        title = "Test",
        state = "OPEN",
        labels = { { name = "status:in-progress" } },
      }
      local label, reason = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:in-progress", label)
      assert.truthy(reason:match("label:"))
    end)

    it("matches status:todo label", function()
      local issue = {
        number = 3,
        title = "Test",
        state = "OPEN",
        labels = { { name = "status:todo" } },
      }
      local label, _ = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:todo", label)
    end)

    it("matches kanban:review label", function()
      local issue = {
        number = 4,
        title = "Test",
        state = "OPEN",
        labels = { { name = "kanban:review" } },
      }
      local label, _ = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:review", label)
    end)

    it("matches bare 'wip' keyword", function()
      local issue = {
        number = 5,
        title = "Test",
        state = "OPEN",
        labels = { { name = "WIP" } },
      }
      local label, _ = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:in-progress", label)
    end)

    it("matches 'done' keyword case-insensitively", function()
      local issue = {
        number = 6,
        title = "Test",
        state = "OPEN",
        labels = { { name = "Done" } },
      }
      local label, _ = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:done", label)
    end)

    it("matches 'completed' keyword", function()
      local issue = {
        number = 7,
        title = "Test",
        state = "OPEN",
        labels = { { name = "completed" } },
      }
      local label, _ = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:done", label)
    end)

    it("matches 'in review' keyword", function()
      local issue = {
        number = 8,
        title = "Test",
        state = "OPEN",
        labels = { { name = "in review" } },
      }
      local label, _ = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:review", label)
    end)

    it("defaults to backlog when no labels match", function()
      local issue = {
        number = 9,
        title = "Test",
        state = "OPEN",
        labels = { { name = "type: bug" } },
      }
      local label, reason = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:backlog", label)
      assert.equals("default", reason)
    end)

    it("defaults to backlog with no labels at all", function()
      local issue = {
        number = 10,
        title = "Test",
        state = "OPEN",
        labels = {},
      }
      local label, reason = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:backlog", label)
      assert.equals("default", reason)
    end)

    it("closed takes priority over label match", function()
      local issue = {
        number = 11,
        title = "Test",
        state = "CLOSED",
        labels = { { name = "status:in-progress" } },
      }
      local label, reason = triage._classify_issue(issue, pattern_map)
      assert.equals("okuban:done", label)
      assert.equals("closed", reason)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- build_plan
  -- -----------------------------------------------------------------------
  describe("build_plan", function()
    it("returns nil when no issues need triage", function()
      -- All issues already have okuban labels
      local issues = vim.json.encode({
        { number = 1, title = "A", state = "OPEN", labels = { { name = "okuban:todo" } } },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = issues },
      })

      local done = false
      local result = nil
      triage.build_plan(function(plan)
        done = true
        result = plan
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result)
    end)

    it("builds plan with mixed open and closed issues", function()
      local issues = vim.json.encode({
        { number = 1, title = "Closed bug", state = "CLOSED", labels = {} },
        { number = 2, title = "Open feature", state = "OPEN", labels = {} },
        { number = 3, title = "Has status", state = "OPEN", labels = { { name = "status:todo" } } },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = issues },
      })

      local done = false
      local result = nil
      triage.build_plan(function(plan)
        done = true
        result = plan
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(3, #result.entries)
      assert.equals(1, result.summary.done)
      assert.equals(1, result.summary.matched)
      assert.equals(1, result.summary.backlog)
      assert.equals(1, #result.ai_candidates)
    end)

    it("skips issues that already have okuban labels", function()
      local issues = vim.json.encode({
        { number = 1, title = "Already triaged", state = "OPEN", labels = { { name = "okuban:todo" } } },
        { number = 2, title = "Untriaged", state = "OPEN", labels = {} },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = issues },
      })

      local done = false
      local result = nil
      triage.build_plan(function(plan)
        done = true
        result = plan
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(1, #result.entries)
      assert.equals(2, result.entries[1].number)
    end)

    it("returns nil on fetch failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "network error" },
      })

      local done = false
      local result = "not nil"
      triage.build_plan(function(plan)
        done = true
        result = plan
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result)
    end)

    it("respects include_closed = false", function()
      config.setup({ triage = { include_closed = false } })
      -- Re-require after config change
      package.loaded["okuban.triage"] = nil
      triage = require("okuban.triage")

      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "[]" },
      })

      local done = false
      triage.build_plan(function()
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      -- The gh command should use --state open (not --state all)
      assert.truthy(vim.tbl_contains(calls[1].cmd, "open"))
    end)
  end)

  -- -----------------------------------------------------------------------
  -- apply_plan
  -- -----------------------------------------------------------------------
  describe("apply_plan", function()
    it("fires gh issue edit --add-label for each entry", function()
      local plan = {
        entries = {
          { number = 1, title = "A", target_label = "okuban:done", reason = "closed" },
          { number = 2, title = "B", target_label = "okuban:backlog", reason = "default" },
        },
        summary = { done = 1, matched = 0, backlog = 1 },
        ai_candidates = {},
      }

      local calls = helpers.mock_vim_system({
        { code = 0 },
        { code = 0 },
      })

      local done = false
      local result_applied = 0
      local result_failed = 0
      triage.apply_plan(plan, function(applied, failed)
        done = true
        result_applied = applied
        result_failed = failed
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(2, result_applied)
      assert.equals(0, result_failed)
      assert.equals(2, #calls)

      -- Verify commands use --add-label (not --remove-label)
      for _, call in ipairs(calls) do
        assert.truthy(vim.tbl_contains(call.cmd, "--add-label"))
        assert.is_nil(vim.tbl_contains(call.cmd, "--remove-label") and true or nil)
      end
    end)

    it("counts failures correctly", function()
      local plan = {
        entries = {
          { number = 1, title = "A", target_label = "okuban:done", reason = "closed" },
          { number = 2, title = "B", target_label = "okuban:backlog", reason = "default" },
        },
        summary = {},
        ai_candidates = {},
      }

      helpers.mock_vim_system({
        { code = 0 },
        { code = 1, stderr = "error" },
      })

      local done = false
      local result_applied = 0
      local result_failed = 0
      triage.apply_plan(plan, function(applied, failed)
        done = true
        result_applied = applied
        result_failed = failed
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(1, result_applied)
      assert.equals(1, result_failed)
    end)

    it("handles empty plan immediately", function()
      local plan = {
        entries = {},
        summary = {},
        ai_candidates = {},
      }

      local done = false
      local result_applied = 0
      triage.apply_plan(plan, function(applied, failed)
        done = true
        result_applied = applied
        assert.equals(0, failed)
      end)

      -- Should complete synchronously (no vim.wait needed, but use it for safety)
      vim.wait(100, function()
        return done
      end)

      assert.is_true(done)
      assert.equals(0, result_applied)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- show_confirmation
  -- -----------------------------------------------------------------------
  describe("show_confirmation", function()
    it("renders correct summary lines", function()
      local plan = {
        entries = {
          { number = 1, title = "Closed bug", target_label = "okuban:done", reason = "closed", state = "CLOSED" },
          {
            number = 2,
            title = "Has status",
            target_label = "okuban:todo",
            reason = "label: status:todo",
            state = "OPEN",
          },
          { number = 3, title = "Open feat", target_label = "okuban:backlog", reason = "default", state = "OPEN" },
        },
        summary = { done = 1, matched = 1, backlog = 1 },
        ai_candidates = { { number = 3, title = "Open feat" } },
      }

      -- Just verify it doesn't error and creates a window
      local win_count_before = #vim.api.nvim_list_wins()
      triage.show_confirmation(plan, function() end)
      local win_count_after = #vim.api.nvim_list_wins()

      -- A new floating window should have been created
      assert.is_true(win_count_after > win_count_before)

      -- Clean up: close all floating windows
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local win_cfg = vim.api.nvim_win_get_config(w)
        if win_cfg.relative and win_cfg.relative ~= "" then
          vim.api.nvim_win_close(w, true)
        end
      end
    end)

    it("shows AI option only when claude is available and candidates exist", function()
      -- Mock claude as unavailable
      package.loaded["okuban.claude"] = {
        is_available = function()
          return false
        end,
      }

      local plan = {
        entries = {
          { number = 1, title = "Open", target_label = "okuban:backlog", reason = "default", state = "OPEN" },
        },
        summary = { done = 0, matched = 0, backlog = 1 },
        ai_candidates = { { number = 1, title = "Open" } },
      }

      local win_count_before = #vim.api.nvim_list_wins()
      triage.show_confirmation(plan, function() end)
      local win_count_after = #vim.api.nvim_list_wins()
      assert.is_true(win_count_after > win_count_before)

      -- Find the confirmation window and check its buffer content
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local win_cfg = vim.api.nvim_win_get_config(w)
        if win_cfg.relative and win_cfg.relative ~= "" then
          local buf = vim.api.nvim_win_get_buf(w)
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local has_ai_line = false
          for _, line in ipairs(lines) do
            if line:match("%[a%] AI triage") then
              has_ai_line = true
            end
          end
          -- Should NOT have AI line since claude is unavailable
          assert.is_false(has_ai_line)
          vim.api.nvim_win_close(w, true)
        end
      end

      -- Restore
      package.loaded["okuban.claude"] = nil
    end)
  end)

  -- -----------------------------------------------------------------------
  -- config defaults
  -- -----------------------------------------------------------------------
  describe("config", function()
    it("has triage defaults", function()
      local cfg = config.get()
      assert.is_true(cfg.triage.enabled)
      assert.is_true(cfg.triage.include_closed)
      assert.is_true(cfg.triage.ai_enabled)
    end)

    it("can disable triage via setup", function()
      config.setup({ triage = { enabled = false } })
      assert.is_false(config.get().triage.enabled)
    end)
  end)
end)

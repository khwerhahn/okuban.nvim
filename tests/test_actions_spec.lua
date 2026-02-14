local helpers = require("tests.helpers")

describe("okuban.ui.actions", function()
  local actions, api, config

  before_each(function()
    package.loaded["okuban.ui.actions"] = nil
    package.loaded["okuban.api"] = nil
    package.loaded["okuban.config"] = nil
    config = require("okuban.config")
    api = require("okuban.api")
    actions = require("okuban.ui.actions")
  end)

  after_each(function()
    actions.close()
    helpers.restore_vim_system()
  end)

  describe("close_issue API", function()
    it("calls gh issue close with correct number", function()
      local calls = helpers.mock_vim_system({
        { code = 0 },
      })

      local done = false
      local result = nil
      api.close_issue(42, function(ok)
        done = true
        result = ok
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(result)
      assert.truthy(vim.tbl_contains(calls[1].cmd, "issue"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "close"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "42"))
    end)

    it("returns error on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "not found" },
      })

      local done = false
      local result_ok = nil
      local result_err = nil
      api.close_issue(99, function(ok, err)
        done = true
        result_ok = ok
        result_err = err
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result_ok)
      assert.truthy(result_err)
    end)
  end)

  describe("assign_issue API", function()
    it("calls gh issue edit with --add-assignee @me", function()
      local calls = helpers.mock_vim_system({
        { code = 0 },
      })

      local done = false
      local result = nil
      api.assign_issue(42, function(ok)
        done = true
        result = ok
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(result)
      assert.truthy(vim.tbl_contains(calls[1].cmd, "issue"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "edit"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "--add-assignee"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "@me"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "42"))
    end)

    it("returns error on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "permission denied" },
      })

      local done = false
      local result_ok = nil
      api.assign_issue(42, function(ok)
        done = true
        result_ok = ok
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result_ok)
    end)
  end)

  describe("view_issue_in_browser API", function()
    it("calls gh issue view --web", function()
      local calls = helpers.mock_vim_system({
        { code = 0 },
      })

      api.view_issue_in_browser(42)

      -- Give async a moment
      vim.wait(500, function()
        return #calls > 0
      end)

      assert.truthy(vim.tbl_contains(calls[1].cmd, "issue"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "view"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "--web"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "42"))
    end)
  end)

  describe("build_actions context", function()
    it("includes close/assign/code for open issues", function()
      local issue = { number = 42, title = "Test", state = "OPEN" }
      local board = {} -- minimal stub
      local action_list = actions._build_actions(issue, board)
      local keys = {}
      for _, a in ipairs(action_list) do
        keys[a.key] = true
      end
      assert.is_true(keys["m"]) -- move always
      assert.is_true(keys["v"]) -- view always
      assert.is_true(keys["c"]) -- close for open
      assert.is_true(keys["a"]) -- assign for open
    end)

    it("excludes close/assign/code for closed issues", function()
      local issue = { number = 42, title = "Test", state = "CLOSED" }
      local board = {}
      local action_list = actions._build_actions(issue, board)
      local keys = {}
      for _, a in ipairs(action_list) do
        keys[a.key] = true
      end
      assert.is_true(keys["m"]) -- move always available
      assert.is_true(keys["v"]) -- view always available
      assert.is_nil(keys["c"]) -- no close
      assert.is_nil(keys["a"]) -- no assign
      assert.is_nil(keys["x"]) -- no code
    end)
  end)

  describe("execute_action", function()
    it("finds move action for open issue", function()
      local issue = { number = 42, title = "Test", state = "OPEN" }
      local board = {}
      local action_list = actions._build_actions(issue, board)
      local found = false
      for _, a in ipairs(action_list) do
        if a.key == "m" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("returns false for unknown key", function()
      local issue = { number = 42, title = "Test", state = "OPEN" }
      local board = {}
      local result = actions.execute_action("z", issue, board)
      assert.is_false(result)
    end)

    it("returns false for closed-issue-only actions on closed issues", function()
      local issue = { number = 42, title = "Test", state = "CLOSED" }
      local board = {}
      local result = actions.execute_action("c", issue, board)
      assert.is_false(result)
    end)
  end)

  describe("open_actions keymap", function()
    it("is configured as Enter by default", function()
      local keymaps = config.get().keymaps
      assert.equals("<CR>", keymaps.open_actions)
    end)

    it("can be overridden in setup", function()
      config.setup({ keymaps = { open_actions = "<Space>" } })
      assert.equals("<Space>", config.get().keymaps.open_actions)
      -- Other keymaps preserved
      assert.equals("h", config.get().keymaps.column_left)
    end)
  end)
end)

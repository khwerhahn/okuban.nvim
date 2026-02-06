local helpers = require("tests.helpers")

describe("okuban.api fetch", function()
  local api, config

  before_each(function()
    package.loaded["okuban.api"] = nil
    package.loaded["okuban.config"] = nil
    config = require("okuban.config")
    api = require("okuban.api")
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("fetch_column", function()
    it("parses JSON response into issue list", function()
      local json = vim.json.encode({
        {
          number = 42,
          title = "Add board rendering",
          assignees = { { login = "alice" } },
          labels = {},
          state = "OPEN",
        },
        { number = 43, title = "Fix navigation", assignees = {}, labels = {}, state = "OPEN" },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api.fetch_column("okuban:todo", function(issues)
        done = true
        result = issues
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals(2, #result)
      assert.equals(42, result[1].number)
      assert.equals("Add board rendering", result[1].title)
      assert.equals(43, result[2].number)
    end)

    it("returns empty list on JSON parse error", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "not valid json{{{" },
      })

      local done = false
      local result = nil
      api.fetch_column("okuban:todo", function(issues)
        done = true
        result = issues
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals(0, #result)
    end)

    it("returns nil with error on command failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "network error" },
      })

      local done = false
      local result_issues = "not_nil"
      local result_err = nil
      api.fetch_column("okuban:todo", function(issues, err)
        done = true
        result_issues = issues
        result_err = err
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_nil(result_issues)
      assert.truthy(result_err)
    end)

    it("includes correct gh command arguments", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "[]" },
      })

      local done = false
      api.fetch_column("okuban:in-progress", function()
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "issue"))
      assert.truthy(vim.tbl_contains(cmd, "list"))
      assert.truthy(vim.tbl_contains(cmd, "--label"))
      assert.truthy(vim.tbl_contains(cmd, "okuban:in-progress"))
      assert.truthy(vim.tbl_contains(cmd, "--json"))
      assert.truthy(vim.tbl_contains(cmd, "--limit"))
      assert.truthy(vim.tbl_contains(cmd, "100"))
    end)
  end)

  describe("fetch_all_columns", function()
    it("returns structured board data with all columns", function()
      -- Mock responses for 5 columns + 1 unsorted fetch = 6 calls
      local responses = {}
      for i = 1, 5 do
        responses[i] = { code = 0, stdout = "[]" }
      end
      -- Column 2 (todo) has an issue
      responses[2] = {
        code = 0,
        stdout = vim.json.encode({
          { number = 10, title = "Test issue", assignees = {}, labels = {}, state = "OPEN" },
        }),
      }
      -- Unsorted fetch (all issues) returns one issue without kanban labels
      responses[6] = {
        code = 0,
        stdout = vim.json.encode({
          { number = 10, title = "Test issue", assignees = {}, labels = { { name = "okuban:todo" } }, state = "OPEN" },
          { number = 99, title = "Unsorted issue", assignees = {}, labels = { { name = "bug" } }, state = "OPEN" },
        }),
      }
      helpers.mock_vim_system(responses)

      local done = false
      local result = nil
      api.fetch_all_columns(function(data)
        done = true
        result = data
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(5, #result.columns)
      assert.equals("Backlog", result.columns[1].name)
      assert.equals("Todo", result.columns[2].name)
      assert.equals(1, #result.columns[2].issues)
      assert.equals(10, result.columns[2].issues[1].number)
      assert.is_not_nil(result.unsorted)
      assert.equals(1, #result.unsorted)
      assert.equals(99, result.unsorted[1].number)
    end)

    it("excludes unsorted when show_unsorted is false", function()
      config.setup({ show_unsorted = false })
      package.loaded["okuban.api"] = nil
      api = require("okuban.api")

      local responses = {}
      for i = 1, 5 do
        responses[i] = { code = 0, stdout = "[]" }
      end
      local calls = helpers.mock_vim_system(responses)

      local done = false
      local result = nil
      api.fetch_all_columns(function(data)
        done = true
        result = data
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.equals(5, #result.columns)
      assert.is_nil(result.unsorted)
      assert.equals(5, #calls) -- only 5 calls, no unsorted fetch
    end)
  end)

  describe("create_all_labels", function()
    it("creates 5 kanban labels by default", function()
      local responses = {}
      for i = 1, 5 do
        responses[i] = { code = 0 }
      end
      local calls = helpers.mock_vim_system(responses)

      local done = false
      local created_count = 0
      api.create_all_labels(false, function(created, failed)
        done = true
        created_count = created
        assert.equals(0, failed)
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.equals(5, #calls)
      assert.equals(5, created_count)
      -- Verify first label command
      assert.truthy(vim.tbl_contains(calls[1].cmd, "label"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "create"))
      assert.truthy(vim.tbl_contains(calls[1].cmd, "--force"))
    end)

    it("creates all ~17 labels when full is true", function()
      local responses = {}
      for i = 1, 17 do
        responses[i] = { code = 0 }
      end
      local calls = helpers.mock_vim_system(responses)

      local done = false
      local created_count = 0
      api.create_all_labels(true, function(created, failed)
        done = true
        created_count = created
        assert.equals(0, failed)
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.equals(17, #calls)
      assert.equals(17, created_count)
    end)

    it("reports failures correctly", function()
      local responses = {}
      for i = 1, 5 do
        responses[i] = { code = 0 }
      end
      responses[3] = { code = 1, stderr = "permission denied" }
      helpers.mock_vim_system(responses)

      local done = false
      api.create_all_labels(false, function(created, failed)
        done = true
        assert.equals(4, created)
        assert.equals(1, failed)
      end)

      vim.wait(2000, function()
        return done
      end)
    end)
  end)
end)

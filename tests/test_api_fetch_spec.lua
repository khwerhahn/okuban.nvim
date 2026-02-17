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
      api.fetch_column("okuban:todo", nil, nil, function(issues)
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
      api.fetch_column("okuban:todo", nil, nil, function(issues)
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
      api.fetch_column("okuban:todo", nil, nil, function(issues, err)
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
      api.fetch_column("okuban:in-progress", nil, nil, function()
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
      assert.truthy(vim.tbl_contains(cmd, "--state"))
      assert.truthy(vim.tbl_contains(cmd, "open"))
    end)

    it("passes state parameter to gh command", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "[]" },
      })

      local done = false
      api.fetch_column("okuban:done", "all", nil, function()
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "--state"))
      assert.truthy(vim.tbl_contains(cmd, "all"))
    end)

    it("passes custom limit to gh command", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "[]" },
      })

      local done = false
      api.fetch_column("okuban:done", "all", 20, function()
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "--limit"))
      assert.truthy(vim.tbl_contains(cmd, "20"))
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

    it("passes Done column limit to fetch_column", function()
      -- Disable lazy loading to test per-column limits directly
      config.setup({ initial_fetch_limit = 0 })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      local responses = {}
      for i = 1, 6 do
        responses[i] = { code = 0, stdout = "[]" }
      end
      local calls = helpers.mock_vim_system(responses)

      local done = false
      api.fetch_all_columns(function()
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      -- The 5th column (Done) should use --limit 20
      local done_cmd = calls[5].cmd
      local limit_val = nil
      for i, v in ipairs(done_cmd) do
        if v == "--limit" then
          limit_val = done_cmd[i + 1]
          break
        end
      end
      assert.equals("20", limit_val)

      -- Other columns should use --limit 100 (default)
      local todo_cmd = calls[2].cmd
      local todo_limit = nil
      for i, v in ipairs(todo_cmd) do
        if v == "--limit" then
          todo_limit = todo_cmd[i + 1]
          break
        end
      end
      assert.equals("100", todo_limit)
    end)

    it("includes limit field in returned board data", function()
      local responses = {}
      for i = 1, 6 do
        responses[i] = { code = 0, stdout = "[]" }
      end
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

      -- Done column (index 5) should have limit = 20
      assert.equals(20, result.columns[5].limit)
      -- Other columns should have nil limit
      assert.is_nil(result.columns[1].limit)
    end)

    it("passes column state to fetch_column for Done column", function()
      local responses = {}
      for i = 1, 6 do
        responses[i] = { code = 0, stdout = "[]" }
      end
      local calls = helpers.mock_vim_system(responses)

      local done = false
      api.fetch_all_columns(function()
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      -- The 5th column (Done) should use --state all
      local done_cmd = calls[5].cmd
      -- Find the index of "--state" and check the value after it
      local state_val = nil
      for i, v in ipairs(done_cmd) do
        if v == "--state" then
          state_val = done_cmd[i + 1]
          break
        end
      end
      assert.equals("all", state_val)

      -- Other columns should use --state open (default)
      local todo_cmd = calls[2].cmd
      local todo_state = nil
      for i, v in ipairs(todo_cmd) do
        if v == "--state" then
          todo_state = todo_cmd[i + 1]
          break
        end
      end
      assert.equals("open", todo_state)
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

  describe("fetch_sub_issue_counts", function()
    it("returns empty table on empty input", function()
      local done = false
      local result = nil
      -- Need api_labels module directly for label-mode fetch
      local api_labels = require("okuban.api_labels")
      api_labels.fetch_sub_issue_counts({}, function(counts)
        done = true
        result = counts
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_not_nil(result)
      assert.equals(0, vim.tbl_count(result))
    end)

    it("parses GraphQL response correctly", function()
      -- First call: detect_repo_info (gh repo view)
      -- Second call: GraphQL query
      local graphql_response = vim.json.encode({
        data = {
          repository = {
            i10 = { subIssuesSummary = { total = 3, completed = 1 } },
            i20 = { subIssuesSummary = { total = 0, completed = 0 } },
            i30 = { subIssuesSummary = { total = 5, completed = 5 } },
          },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = "alice|myrepo" }, -- detect_repo_info
        { code = 0, stdout = graphql_response }, -- GraphQL query
      })

      local api_labels = require("okuban.api_labels")
      -- Reset repo info cache
      api._reset_repo_info()

      local done = false
      local result = nil
      api_labels.fetch_sub_issue_counts({ 10, 20, 30 }, function(counts)
        done = true
        result = counts
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      -- Issue 10: total=3 > 0, should be in result
      assert.is_not_nil(result[10])
      assert.equals(3, result[10].total)
      assert.equals(1, result[10].completed)
      -- Issue 20: total=0, should NOT be in result
      assert.is_nil(result[20])
      -- Issue 30: total=5 > 0, should be in result
      assert.is_not_nil(result[30])
      assert.equals(5, result[30].total)
      assert.equals(5, result[30].completed)
    end)

    it("handles API errors gracefully", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "alice|myrepo" }, -- detect_repo_info
        { code = 1, stderr = "GraphQL error" }, -- GraphQL fails
      })

      local api_labels = require("okuban.api_labels")
      api._reset_repo_info()

      local done = false
      local result = nil
      api_labels.fetch_sub_issue_counts({ 10, 20 }, function(counts)
        done = true
        result = counts
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(0, vim.tbl_count(result))
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

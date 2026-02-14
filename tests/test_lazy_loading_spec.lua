local helpers = require("tests.helpers")

describe("okuban lazy loading", function()
  local api, config

  before_each(function()
    package.loaded["okuban.api"] = nil
    package.loaded["okuban.api_labels"] = nil
    package.loaded["okuban.config"] = nil
    config = require("okuban.config")
    api = require("okuban.api")
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  --- Generate N issues as JSON for mock responses.
  ---@param count integer
  ---@return string json
  local function make_issues_json(count)
    local issues = {}
    for i = 1, count do
      table.insert(issues, {
        number = i,
        title = "Issue " .. i,
        assignees = {},
        labels = {},
        state = "OPEN",
      })
    end
    return vim.json.encode(issues)
  end

  describe("fetch_all_columns with initial_fetch_limit", function()
    it("uses initial_fetch_limit for gh --limit when set", function()
      config.setup({ initial_fetch_limit = 5, show_unsorted = false })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      local responses = {}
      for i = 1, 5 do
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

      -- First 4 columns (no per-column limit) should use initial_fetch_limit = 5
      for i = 1, 4 do
        local cmd = calls[i].cmd
        local limit_val = nil
        for j, v in ipairs(cmd) do
          if v == "--limit" then
            limit_val = cmd[j + 1]
            break
          end
        end
        assert.equals("5", limit_val, "Column " .. i .. " should use initial_fetch_limit")
      end

      -- Column 5 (Done, limit=20) should use min(5, 20) = 5
      local done_cmd = calls[5].cmd
      local done_limit = nil
      for j, v in ipairs(done_cmd) do
        if v == "--limit" then
          done_limit = done_cmd[j + 1]
          break
        end
      end
      assert.equals("5", done_limit)
    end)

    it("disables lazy loading when initial_fetch_limit is 0", function()
      config.setup({ initial_fetch_limit = 0, show_unsorted = false })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      local responses = {}
      for i = 1, 5 do
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

      -- Column 1 (no per-column limit) should use full limit = 100
      local cmd = calls[1].cmd
      local limit_val = nil
      for j, v in ipairs(cmd) do
        if v == "--limit" then
          limit_val = cmd[j + 1]
          break
        end
      end
      assert.equals("100", limit_val)
    end)

    it("sets has_more=true when fetched count >= initial_fetch_limit", function()
      config.setup({ initial_fetch_limit = 3, show_unsorted = false })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      local responses = {}
      -- Column 1: exactly 3 issues (matches limit)
      responses[1] = { code = 0, stdout = make_issues_json(3) }
      -- Column 2: 1 issue (below limit)
      responses[2] = { code = 0, stdout = make_issues_json(1) }
      for i = 3, 5 do
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

      assert.is_true(result.columns[1].has_more)
      assert.is_false(result.columns[2].has_more)
      assert.is_false(result.columns[3].has_more)
    end)

    it("sets expanded=false on initial fetch", function()
      config.setup({ initial_fetch_limit = 5, show_unsorted = false })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      local responses = {}
      for i = 1, 5 do
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

      for i = 1, 5 do
        assert.is_false(result.columns[i].expanded, "Column " .. i .. " should not be expanded")
      end
    end)
  end)

  describe("expand_column (labels)", function()
    it("re-fetches with full limit and sets expanded=true", function()
      config.setup({ initial_fetch_limit = 2, show_unsorted = false })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      -- Initial fetch: 5 columns
      local responses = {}
      for i = 1, 5 do
        responses[i] = { code = 0, stdout = make_issues_json(2) }
      end
      helpers.mock_vim_system(responses)

      local done = false
      api.fetch_all_columns(function()
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)
      helpers.restore_vim_system()

      -- Now expand column 1
      local expand_responses = {
        { code = 0, stdout = make_issues_json(15) },
      }
      helpers.mock_vim_system(expand_responses)

      local expand_done = false
      local expand_ok = nil
      api.expand_column(1, function(ok)
        expand_done = true
        expand_ok = ok
      end)

      vim.wait(2000, function()
        return expand_done
      end)

      assert.is_true(expand_ok)
      -- Check that board cache was updated
      local cached = api.get_cached_board_data(60)
      assert.is_not_nil(cached)
      assert.equals(15, #cached.columns[1].issues)
      assert.is_true(cached.columns[1].expanded)
    end)

    it("is a no-op when column is already expanded", function()
      config.setup({ initial_fetch_limit = 2, show_unsorted = false })
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      api = require("okuban.api")

      -- Initial fetch
      local responses = {}
      for i = 1, 5 do
        responses[i] = { code = 0, stdout = make_issues_json(2) }
      end
      helpers.mock_vim_system(responses)

      local done = false
      api.fetch_all_columns(function()
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)
      helpers.restore_vim_system()

      -- Expand column 1
      helpers.mock_vim_system({ { code = 0, stdout = make_issues_json(10) } })
      local expand_done = false
      api.expand_column(1, function()
        expand_done = true
      end)
      vim.wait(2000, function()
        return expand_done
      end)
      helpers.restore_vim_system()

      -- Expand again — should be a no-op (no new vim.system call)
      local calls = helpers.mock_vim_system({})
      local done2 = false
      local ok2 = nil
      api.expand_column(1, function(ok)
        done2 = true
        ok2 = ok
      end)

      vim.wait(1000, function()
        return done2
      end)

      assert.is_true(ok2)
      assert.equals(0, #calls) -- no API call made
    end)
  end)

  describe("build_board_data (project)", function()
    it("respects initial_limit for display capping", function()
      local api_project = require("okuban.api_project")
      api_project.reset_cache()

      local items = {}
      for i = 1, 15 do
        table.insert(items, {
          id = "item_" .. i,
          content = {
            number = i,
            title = "Issue " .. i,
            state = "OPEN",
            assignees = { nodes = {} },
            labels = { nodes = {} },
          },
          fieldValueByName = { optionId = "opt1", name = "Todo" },
        })
      end

      local status_field = {
        id = "field1",
        options = { { id = "opt1", name = "Todo" } },
      }

      local board_data = api_project.build_board_data(items, status_field, false, 20, 5)

      -- Should be capped to 5 (initial_limit)
      assert.equals(5, #board_data.columns[1].issues)
      assert.is_true(board_data.columns[1].has_more)
      assert.is_false(board_data.columns[1].expanded)
    end)

    it("uses done_limit when no initial_limit", function()
      local api_project = require("okuban.api_project")
      api_project.reset_cache()

      local items = {}
      for i = 1, 25 do
        table.insert(items, {
          id = "item_" .. i,
          content = {
            number = i,
            title = "Issue " .. i,
            state = "OPEN",
            assignees = { nodes = {} },
            labels = { nodes = {} },
          },
          fieldValueByName = { optionId = "opt1", name = "Todo" },
        })
      end

      local status_field = {
        id = "field1",
        options = { { id = "opt1", name = "Todo" } },
      }

      local board_data = api_project.build_board_data(items, status_field, false, 20, nil)

      assert.equals(20, #board_data.columns[1].issues)
      assert.is_true(board_data.columns[1].has_more)
    end)
  end)
end)

local helpers = require("tests.helpers")

describe("okuban.ui.move", function()
  local move_mod

  before_each(function()
    package.loaded["okuban.ui.move"] = nil
    package.loaded["okuban.config"] = nil
    package.loaded["okuban.api"] = nil
    package.loaded["okuban.api_labels"] = nil
    package.loaded["okuban.api_project"] = nil
    require("okuban.config")
    move_mod = require("okuban.ui.move")
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("execute_move", function()
    it("calls gh issue edit with correct label swap", function()
      local calls = helpers.mock_vim_system({
        { code = 0 }, -- edit_labels call
        -- fetch_all_columns will fire 6 calls (5 columns + unsorted)
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
      })

      local refreshed = false
      local mock_board = {
        refresh = function()
          refreshed = true
        end,
      }

      move_mod.execute_move(42, "okuban:todo", "okuban:in-progress", "In Progress", mock_board)

      vim.wait(2000, function()
        return #calls >= 1
      end)

      -- Verify the first call is the label edit
      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "issue"))
      assert.truthy(vim.tbl_contains(cmd, "edit"))
      assert.truthy(vim.tbl_contains(cmd, "42"))
      assert.truthy(vim.tbl_contains(cmd, "--remove-label"))
      assert.truthy(vim.tbl_contains(cmd, "okuban:todo"))
      assert.truthy(vim.tbl_contains(cmd, "--add-label"))
      assert.truthy(vim.tbl_contains(cmd, "okuban:in-progress"))

      -- Wait for refresh to trigger
      vim.wait(2000, function()
        return refreshed
      end)
    end)

    it("shows error notification on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "permission denied" },
      })

      local mock_board = {
        refresh = function() end,
      }

      -- Capture notifications from spinner stop (which calls vim.notify)
      local notified_msg = nil
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified_msg = msg
      end

      move_mod.execute_move(42, "okuban:todo", "okuban:in-progress", "In Progress", mock_board)

      vim.wait(2000, function()
        return notified_msg ~= nil
      end)

      vim.notify = orig_notify
      assert.truthy(notified_msg)
      assert.truthy(notified_msg:match("Failed"))
    end)
  end)

  describe("execute_move (project mode)", function()
    it("calls gh project item-edit in project mode", function()
      local config = require("okuban.config")
      config.setup({ source = "project", project = { number = 1, owner = "testowner" } })

      package.loaded["okuban.ui.move"] = nil
      package.loaded["okuban.api"] = nil
      package.loaded["okuban.api_labels"] = nil
      package.loaded["okuban.api_project"] = nil
      move_mod = require("okuban.ui.move")

      -- Pre-populate the project cache
      local api_project = require("okuban.api_project")
      api_project._set_cache("PVT_123", {
        id = "PVTSSF_status",
        options = {
          { id = "opt_todo", name = "Todo" },
          { id = "opt_done", name = "Done" },
        },
      })
      -- Manually set item_map
      api_project.build_board_data({
        {
          id = "PVTI_42",
          content = {
            number = 42,
            title = "Test",
            body = "",
            state = "OPEN",
            assignees = { nodes = {} },
            labels = { nodes = {} },
          },
          fieldValueByName = { name = "Todo", optionId = "opt_todo" },
        },
      }, api_project.get_cached_status_field(), false, 100)

      -- Mock: 1 item-edit call + items refetch for refresh
      local items_json = vim.json.encode({
        data = {
          node = {
            items = {
              pageInfo = { hasNextPage = false },
              nodes = {},
            },
          },
        },
      })
      local calls = helpers.mock_vim_system({
        { code = 0 }, -- item-edit
        { code = 0, stdout = items_json }, -- fetch_all_columns (cached ID/field, only items query)
      })

      local refreshed = false
      local mock_board = {
        refresh = function()
          refreshed = true
        end,
      }

      move_mod.execute_move(42, "opt_todo", "opt_done", "Done", mock_board)

      vim.wait(2000, function()
        return #calls >= 1
      end)

      -- Verify the first call is project item-edit
      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "project"))
      assert.truthy(vim.tbl_contains(cmd, "item-edit"))
      assert.truthy(vim.tbl_contains(cmd, "--id"))
      assert.truthy(vim.tbl_contains(cmd, "PVTI_42"))
      assert.truthy(vim.tbl_contains(cmd, "--single-select-option-id"))
      assert.truthy(vim.tbl_contains(cmd, "opt_done"))

      vim.wait(2000, function()
        return refreshed
      end)
    end)
  end)

  describe("prompt_move", function()
    local picker = require("okuban.ui.picker")

    it("builds target list excluding current column", function()
      -- We test the internal logic by checking that picker.select receives
      -- the right number of options
      local select_items = nil
      local orig_select = picker.select
      picker.select = function(items)
        select_items = items
      end

      local nav = {
        get_selected_issue = function()
          return { number = 42, title = "Test" }
        end,
        get_selected_column_label = function()
          return "okuban:todo"
        end,
      }

      local mock_board = {
        navigation = nav,
      }

      move_mod.prompt_move(mock_board)

      picker.select = orig_select

      -- Should have 4 targets (5 columns minus current)
      assert.is_not_nil(select_items)
      assert.equals(4, #select_items)
      -- "Todo" should not be in the list
      for _, item in ipairs(select_items) do
        assert.is_not.equals("Todo", item.name)
      end
    end)

    it("uses board.data.columns when available", function()
      local select_items = nil
      local orig_select = picker.select
      picker.select = function(items)
        select_items = items
      end

      local nav = {
        get_selected_issue = function()
          return { number = 42, title = "Test" }
        end,
        get_selected_column_label = function()
          return "opt_a"
        end,
      }

      local mock_board = {
        navigation = nav,
        data = {
          columns = {
            { label = "opt_a", name = "Alpha" },
            { label = "opt_b", name = "Beta" },
            { label = "opt_c", name = "Gamma" },
          },
        },
      }

      move_mod.prompt_move(mock_board)

      picker.select = orig_select

      -- Should have 2 targets (3 project columns minus current)
      assert.is_not_nil(select_items)
      assert.equals(2, #select_items)
      assert.equals("Beta", select_items[1].name)
      assert.equals("Gamma", select_items[2].name)
    end)

    it("does nothing when no issue is selected", function()
      local select_called = false
      local orig_select = picker.select
      picker.select = function()
        select_called = true
      end

      local nav = {
        get_selected_issue = function()
          return nil
        end,
        get_selected_column_label = function()
          return "okuban:todo"
        end,
      }

      move_mod.prompt_move({ navigation = nav })

      picker.select = orig_select
      assert.is_false(select_called)
    end)
  end)
end)

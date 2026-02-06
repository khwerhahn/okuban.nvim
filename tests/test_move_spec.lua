local helpers = require("tests.helpers")

describe("okuban.ui.move", function()
  local move_mod

  before_each(function()
    package.loaded["okuban.ui.move"] = nil
    package.loaded["okuban.config"] = nil
    package.loaded["okuban.api"] = nil
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

      local done = false
      -- Capture notification
      local notified_msg = nil
      local orig_notify = vim.notify
      vim.notify = function(msg)
        notified_msg = msg
        done = true
      end

      move_mod.execute_move(42, "okuban:todo", "okuban:in-progress", "In Progress", mock_board)

      vim.wait(2000, function()
        return done
      end)

      vim.notify = orig_notify
      assert.truthy(notified_msg)
      assert.truthy(notified_msg:match("Failed"))
    end)
  end)

  describe("prompt_move", function()
    it("builds target list excluding current column", function()
      -- We test the internal logic by checking that vim.ui.select receives
      -- the right number of options
      local select_items = nil
      local orig_select = vim.ui.select
      vim.ui.select = function(items)
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

      vim.ui.select = orig_select

      -- Should have 4 targets (5 columns minus current)
      assert.is_not_nil(select_items)
      assert.equals(4, #select_items)
      -- "Todo" should not be in the list
      for _, name in ipairs(select_items) do
        assert.is_not.equals("Todo", name)
      end
    end)

    it("does nothing when no issue is selected", function()
      local select_called = false
      local orig_select = vim.ui.select
      vim.ui.select = function()
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

      vim.ui.select = orig_select
      assert.is_false(select_called)
    end)
  end)
end)

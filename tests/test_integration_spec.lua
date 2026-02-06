local helpers = require("tests.helpers")

describe("okuban integration", function()
  local api, config, Navigation

  before_each(function()
    -- Reset all modules
    for key, _ in pairs(package.loaded) do
      if key:match("^okuban") then
        package.loaded[key] = nil
      end
    end
    config = require("okuban.config")
    api = require("okuban.api")
    Navigation = require("okuban.ui.navigation")
    api._reset_preflight()
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("full flow with mock data", function()
    it("navigation state transitions work end-to-end", function()
      -- Simulate a board with 3 columns of varying sizes
      local columns = {
        {
          name = "Todo",
          issues = {
            { number = 1, title = "First task" },
            { number = 2, title = "Second task" },
            { number = 3, title = "Third task" },
          },
          card_ranges = {
            { start_line = 1, end_line = 1 },
            { start_line = 2, end_line = 2 },
            { start_line = 3, end_line = 3 },
          },
        },
        {
          name = "In Progress",
          issues = {
            { number = 4, title = "Active work" },
          },
          card_ranges = {
            { start_line = 1, end_line = 1 },
          },
        },
        {
          name = "Done",
          issues = {
            { number = 5, title = "Completed" },
            { number = 6, title = "Also done" },
          },
          card_ranges = {
            { start_line = 1, end_line = 1 },
            { start_line = 2, end_line = 2 },
          },
        },
      }

      local mock_board = {
        columns = columns,
        windows = { 1, 2, 3 },
        buffers = { 1, 2, 3 },
        data = { columns = columns },
      }

      local nav = Navigation.new(mock_board)
      -- Stub UI methods since we have no real windows
      nav._focus_window = function() end
      nav.highlight_current = function() end

      -- Start at column 1, card 1
      assert.equals(1, nav.column_index)
      assert.equals(1, nav.card_index)
      assert.equals(1, nav:get_selected_issue().number)

      -- Move down through todo column
      nav:move_down()
      assert.equals(2, nav.card_index)
      assert.equals(2, nav:get_selected_issue().number)

      nav:move_down()
      assert.equals(3, nav.card_index)

      -- Move right to "In Progress" - card_index should clamp to 1
      nav:move_right()
      assert.equals(2, nav.column_index)
      assert.equals(1, nav.card_index)
      assert.equals(4, nav:get_selected_issue().number)

      -- Move right to "Done"
      nav:move_right()
      assert.equals(3, nav.column_index)
      assert.equals(1, nav.card_index)

      -- Move down in "Done"
      nav:move_down()
      assert.equals(2, nav.card_index)
      assert.equals(6, nav:get_selected_issue().number)

      -- Move left back to "In Progress" - should clamp to 1
      nav:move_left()
      assert.equals(2, nav.column_index)
      assert.equals(1, nav.card_index)

      -- Boundary: can't move right past last column
      nav.column_index = 3
      nav:move_right()
      assert.equals(3, nav.column_index)

      -- Boundary: can't move left past first column
      nav.column_index = 1
      nav:move_left()
      assert.equals(1, nav.column_index)
    end)
  end)

  describe("api preflight + fetch pipeline", function()
    it("preflight failure prevents fetch", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "not logged in" }, -- auth fails
      })

      local preflight_ok = nil
      api.preflight(function(ok)
        preflight_ok = ok
      end)

      vim.wait(1000, function()
        return preflight_ok ~= nil
      end)

      assert.is_false(preflight_ok)
    end)

    it("successful preflight allows fetch", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "Logged in" }, -- auth
        { code = 0, stdout = "okuban.nvim\n" }, -- repo
        -- fetch: 5 columns + unsorted = 6 calls
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
        { code = 0, stdout = "[]" },
      })

      local fetch_result = nil
      api.preflight(function(ok)
        assert.is_true(ok)
        api.fetch_all_columns(function(data)
          fetch_result = data
        end)
      end)

      vim.wait(3000, function()
        return fetch_result ~= nil
      end)

      assert.is_not_nil(fetch_result)
      assert.equals(5, #fetch_result.columns)
      assert.equals(8, #calls) -- 2 preflight + 6 fetch
    end)
  end)

  describe("edit_labels", function()
    it("constructs correct gh command for label swap", function()
      local calls = helpers.mock_vim_system({
        { code = 0 },
      })

      local done = false
      api.edit_labels(42, "okuban:todo", "okuban:in-progress", function(ok)
        done = true
        assert.is_true(ok)
      end)

      vim.wait(1000, function()
        return done
      end)

      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "issue"))
      assert.truthy(vim.tbl_contains(cmd, "edit"))
      assert.truthy(vim.tbl_contains(cmd, "42"))
      assert.truthy(vim.tbl_contains(cmd, "--remove-label"))
      assert.truthy(vim.tbl_contains(cmd, "okuban:todo"))
      assert.truthy(vim.tbl_contains(cmd, "--add-label"))
      assert.truthy(vim.tbl_contains(cmd, "okuban:in-progress"))
    end)
  end)

  describe("config integration", function()
    it("all modules respect config overrides", function()
      config.setup({
        columns = {
          { label = "custom:a", name = "Alpha", color = "#111111" },
          { label = "custom:b", name = "Beta", color = "#222222" },
        },
        keymaps = { close = "<Esc>" },
      })

      local cfg = config.get()
      assert.equals(2, #cfg.columns)
      assert.equals("custom:a", cfg.columns[1].label)
      assert.equals("<Esc>", cfg.keymaps.close)
    end)
  end)
end)

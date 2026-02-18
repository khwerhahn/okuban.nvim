describe("okuban.ui.navigation", function()
  local Navigation

  before_each(function()
    package.loaded["okuban.ui.navigation"] = nil
    package.loaded["okuban.config"] = nil
    require("okuban.config")
    Navigation = require("okuban.ui.navigation")
  end)

  --- Create a mock board with the given column sizes.
  --- Each card gets a single-line card_range for testing.
  ---@param sizes integer[] Number of issues per column
  ---@return table mock_board
  local function mock_board(sizes)
    local columns = {}
    local windows = {}
    local buffers = {}
    for i, count in ipairs(sizes) do
      local issues = {}
      local card_ranges = {}
      for j = 1, count do
        table.insert(issues, { number = i * 100 + j, title = "Issue " .. j })
        table.insert(card_ranges, { start_line = j, end_line = j })
      end
      table.insert(columns, { name = "Col" .. i, issues = issues, card_ranges = card_ranges })
      table.insert(windows, i) -- fake window handles
      table.insert(buffers, i) -- fake buffer handles
    end
    return {
      columns = columns,
      windows = windows,
      buffers = buffers,
      data = { columns = columns },
      _expanded_col_idx = nil,
      _layout = { board_width = 108, gap = 1, col_width = 20, start_row = 10, start_col = 6, board_height = 22 },
      _restore_column_widths = function(self)
        self._expanded_col_idx = nil
      end,
      _apply_column_expansion = function(self, col_idx)
        self._expanded_col_idx = col_idx
      end,
      get_column_width = function()
        return 20
      end,
    }
  end

  describe("initialization", function()
    it("starts at column 1, card 1", function()
      local board = mock_board({ 3, 2, 5 })
      local nav = Navigation.new(board)
      assert.equals(1, nav.column_index)
      assert.equals(1, nav.card_index)
    end)
  end)

  describe("move_right", function()
    it("moves to the next column", function()
      local board = mock_board({ 3, 2, 5 })
      local nav = Navigation.new(board)
      -- Stub _focus_window and highlight_current since we have no real windows
      nav._focus_window = function() end
      nav.highlight_current = function() end

      nav:move_right()
      assert.equals(2, nav.column_index)
      assert.equals(1, nav.card_index)
    end)

    it("does not move past last column", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      nav:move_right()
      nav:move_right() -- should be clamped
      assert.equals(2, nav.column_index)
    end)

    it("clamps card_index when new column has fewer cards", function()
      local board = mock_board({ 5, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      nav.card_index = 5
      nav:move_right()
      assert.equals(2, nav.column_index)
      assert.equals(2, nav.card_index) -- clamped from 5 to 2
    end)
  end)

  describe("move_left", function()
    it("moves to the previous column", function()
      local board = mock_board({ 3, 2, 5 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      nav.column_index = 3
      nav:move_left()
      assert.equals(2, nav.column_index)
    end)

    it("does not move before first column", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      nav:move_left() -- already at 1
      assert.equals(1, nav.column_index)
    end)
  end)

  describe("move_down", function()
    it("moves to the next card", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      nav:move_down()
      assert.equals(2, nav.card_index)
    end)

    it("does not move past last card when has_more is false", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      nav.card_index = 3
      nav:move_down()
      assert.equals(3, nav.card_index)
    end)

    it("triggers _trigger_expand when at boundary with has_more", function()
      local board = mock_board({ 3 })
      board.columns[1].has_more = true
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      local expand_called = false
      nav._trigger_expand = function()
        expand_called = true
      end

      nav.card_index = 3
      nav:move_down()
      assert.is_true(expand_called)
    end)

    it("does not trigger expand when _expanding is true", function()
      local board = mock_board({ 3 })
      board.columns[1].has_more = true
      local nav = Navigation.new(board)
      nav.highlight_current = function() end
      nav._expanding = true

      local expand_called = false
      nav._trigger_expand = function()
        expand_called = true
      end

      nav.card_index = 3
      nav:move_down()
      assert.is_false(expand_called)
    end)

    it("does not trigger expand on empty column", function()
      local board = mock_board({ 0 })
      board.columns[1].has_more = true
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      local expand_called = false
      nav._trigger_expand = function()
        expand_called = true
      end

      nav:move_down()
      assert.is_false(expand_called)
    end)
  end)

  describe("move_up", function()
    it("moves to the previous card", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      nav.card_index = 3
      nav:move_up()
      assert.equals(2, nav.card_index)
    end)

    it("does not move before first card", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      nav:move_up()
      assert.equals(1, nav.card_index)
    end)
  end)

  describe("get_selected_issue", function()
    it("returns the issue at current position", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav.card_index = 2

      local issue = nav:get_selected_issue()
      assert.is_not_nil(issue)
      assert.equals(102, issue.number) -- col1 issue 2
    end)

    it("returns nil for invalid column", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.column_index = 99

      assert.is_nil(nav:get_selected_issue())
    end)
  end)

  describe("focus_issue", function()
    it("navigates to an issue in the first column", function()
      local board = mock_board({ 3, 2, 5 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      local found = nav:focus_issue(102) -- col1, card 2
      assert.is_true(found)
      assert.equals(1, nav.column_index)
      assert.equals(2, nav.card_index)
    end)

    it("navigates to an issue in a later column", function()
      local board = mock_board({ 3, 2, 5 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      local found = nav:focus_issue(302) -- col3, card 2
      assert.is_true(found)
      assert.equals(3, nav.column_index)
      assert.equals(2, nav.card_index)
    end)

    it("returns false when issue not found", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      local found = nav:focus_issue(999)
      assert.is_false(found)
      -- Position unchanged
      assert.equals(1, nav.column_index)
      assert.equals(1, nav.card_index)
    end)
  end)

  describe("issue_mode", function()
    it("starts with issue_mode false", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      assert.is_false(nav.issue_mode)
    end)

    it("toggles issue_mode on when issue is selected", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      -- Stub header module
      package.loaded["okuban.ui.header"] = {
        enter_issue_mode = function() end,
        exit_issue_mode = function() end,
      }

      nav:toggle_issue_mode()
      assert.is_true(nav.issue_mode)
    end)

    it("toggles issue_mode off when already in issue mode", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      package.loaded["okuban.ui.header"] = {
        enter_issue_mode = function() end,
        exit_issue_mode = function() end,
      }

      nav.issue_mode = true
      nav:toggle_issue_mode()
      assert.is_false(nav.issue_mode)
    end)

    it("does not enter issue_mode on empty column", function()
      local board = mock_board({ 0 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      -- Stub utils.notify to suppress output
      package.loaded["okuban.utils"] = {
        notify = function() end,
      }
      package.loaded["okuban.ui.header"] = {
        enter_issue_mode = function() end,
        exit_issue_mode = function() end,
      }

      nav:toggle_issue_mode()
      assert.is_false(nav.issue_mode)
    end)
  end)

  describe("update_scroll_indicators", function()
    it("method exists on Navigation instances", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      assert.is_function(nav.update_scroll_indicators)
    end)

    it("does not crash on mock boards with fake windows", function()
      local board = mock_board({ 5, 10 })
      local nav = Navigation.new(board)
      -- Should be a no-op since windows are fake integers (not valid win IDs)
      assert.has_no.errors(function()
        nav:update_scroll_indicators()
      end)
    end)
  end)

  describe("tree navigation", function()
    it("starts with _tree_sub_index = 0", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      assert.equals(0, nav._tree_sub_index)
    end)

    it("move_down enters sub-issues when tree is expanded", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      -- Expand tree for issue 101 (col 1, card 1)
      local tree = require("okuban.ui.tree")
      tree.set_expanded(1, 101, {
        { number = 201, title = "Sub1", state = "OPEN" },
        { number = 202, title = "Sub2", state = "OPEN" },
      })

      nav:move_down()
      assert.equals(1, nav._tree_sub_index)
      assert.equals(1, nav.card_index)
    end)

    it("move_down navigates within sub-issues", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      local tree = require("okuban.ui.tree")
      tree.set_expanded(1, 101, {
        { number = 201, title = "Sub1", state = "OPEN" },
        { number = 202, title = "Sub2", state = "OPEN" },
      })

      nav._tree_sub_index = 1
      nav:move_down()
      assert.equals(2, nav._tree_sub_index)
      assert.equals(1, nav.card_index)
    end)

    it("move_down past last sub-issue collapses and moves to next card", function()
      local board = mock_board({ 3 })
      board.columns[1]._visible_items = nil
      local nav = Navigation.new(board)
      nav.highlight_current = function() end
      nav._rerender_column = function() end

      local tree = require("okuban.ui.tree")
      tree.set_expanded(1, 101, {
        { number = 201, title = "Sub1", state = "OPEN" },
      })

      nav._tree_sub_index = 1
      nav:move_down()
      assert.equals(0, nav._tree_sub_index)
      assert.equals(2, nav.card_index)
    end)

    it("move_up from sub_index > 1 decrements", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      nav._tree_sub_index = 2
      nav:move_up()
      assert.equals(1, nav._tree_sub_index)
    end)

    it("move_up from sub_index 1 returns to parent", function()
      local board = mock_board({ 3 })
      local nav = Navigation.new(board)
      nav.highlight_current = function() end

      nav._tree_sub_index = 1
      nav:move_up()
      assert.equals(0, nav._tree_sub_index)
      assert.equals(1, nav.card_index)
    end)

    it("column change resets _tree_sub_index", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end
      nav._rerender_column = function() end

      local tree = require("okuban.ui.tree")
      tree.set_expanded(1, 101, {
        { number = 201, title = "Sub1", state = "OPEN" },
      })
      nav._tree_sub_index = 1

      nav:move_right()
      assert.equals(0, nav._tree_sub_index)
      assert.equals(2, nav.column_index)
    end)

    it("focus_issue resets _tree_sub_index", function()
      local board = mock_board({ 3, 2 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      nav._tree_sub_index = 2
      nav:focus_issue(202) -- col 2, card 2
      assert.equals(0, nav._tree_sub_index)
    end)
  end)

  describe("empty columns", function()
    it("handles column with zero issues", function()
      local board = mock_board({ 0, 3, 0 })
      local nav = Navigation.new(board)
      nav._focus_window = function() end
      nav.highlight_current = function() end

      assert.equals(0, nav:card_count(1))
      assert.equals(3, nav:card_count(2))

      -- Move right to column with issues
      nav:move_right()
      assert.equals(2, nav.column_index)
      assert.equals(1, nav.card_index)

      -- Move right to empty column
      nav:move_right()
      assert.equals(3, nav.column_index)
      assert.equals(1, nav.card_index)
    end)
  end)
end)

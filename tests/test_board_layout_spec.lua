describe("okuban.ui.board layout", function()
  local Board

  before_each(function()
    package.loaded["okuban.ui.board"] = nil
    package.loaded["okuban.config"] = nil
    require("okuban.config")
    Board = require("okuban.ui.board")
  end)

  describe("calculate_layout", function()
    it("calculates correct dimensions for 5 columns on 120x40 terminal", function()
      local layout = Board.calculate_layout(5, 120, 40)
      assert.equals(108, layout.board_width) -- floor(120 * 0.9)
      -- board_height = floor(40*0.8) - 4 (header space) = 28
      assert.equals(28, layout.board_height)
      -- col_width = floor((108 - 4*1) / 5) = floor(104/5) = 20
      assert.equals(20, layout.col_width)
      assert.equals(1, layout.gap)
    end)

    it("calculates correct dimensions for 6 columns on 160x50 terminal", function()
      local layout = Board.calculate_layout(6, 160, 50)
      assert.equals(144, layout.board_width) -- floor(160 * 0.9)
      -- board_height = floor(50*0.8) - 4 = 36
      assert.equals(36, layout.board_height)
      -- col_width = floor((144 - 5*1) / 6) = floor(139/6) = 23
      assert.equals(23, layout.col_width)
    end)

    it("enforces minimum column width of 20", function()
      -- Very narrow terminal: 5 columns on 60 wide
      local layout = Board.calculate_layout(5, 60, 40)
      assert.equals(20, layout.col_width) -- min width enforced
    end)

    it("centers the board on screen", function()
      local layout = Board.calculate_layout(5, 120, 40)
      -- start_col = floor((120 - 108) / 2) = 6
      assert.equals(6, layout.start_col)
      -- total_visual = 3 (header) + 1 (gap) + 28 + 2 (border) = 34
      -- block_start = floor((40 - 34) / 2) = 3
      -- start_row = block_start + 4 (header space) = 7
      assert.equals(7, layout.start_row)
    end)

    it("works with single column", function()
      local layout = Board.calculate_layout(1, 120, 40)
      assert.equals(108, layout.board_width)
      -- col_width = floor((108 - 0) / 1) = 108
      assert.equals(108, layout.col_width)
    end)

    it("handles very small terminal gracefully", function()
      local layout = Board.calculate_layout(5, 30, 10)
      -- Min col_width = 20, board adjusted
      assert.equals(20, layout.col_width)
      assert.is_true(layout.board_height > 0)
    end)

    it("splits available height 75/25 between columns and preview", function()
      local layout = Board.calculate_layout(5, 120, 40, 8)
      -- available = floor(40*0.8) - 4 (header) - 3 (preview border+gap) = 25
      -- board = floor(25 * 0.75) = 18, preview = 25 - 18 = 7
      assert.equals(18, layout.board_height)
      assert.equals(7, layout.preview_height)
      assert.is_not_nil(layout.preview_row)
    end)

    it("positions preview below columns", function()
      local layout = Board.calculate_layout(5, 120, 40, 8)
      -- Preview should start after: start_row + board_height + 2 (border) + 1 (gap)
      assert.equals(layout.start_row + layout.board_height + 3, layout.preview_row)
    end)

    it("has no preview fields when preview_lines is 0", function()
      local layout = Board.calculate_layout(5, 120, 40, 0)
      assert.is_nil(layout.preview_height)
      assert.is_nil(layout.preview_row)
    end)

    it("has no preview fields when preview_lines is nil", function()
      local layout = Board.calculate_layout(5, 120, 40)
      assert.is_nil(layout.preview_height)
      assert.is_nil(layout.preview_row)
    end)

    it("gives preview more space on larger terminals", function()
      local layout = Board.calculate_layout(5, 160, 50, 8)
      -- available = floor(50*0.8) - 4 - 3 = 33
      -- board = floor(33 * 0.75) = 24, preview = 33 - 24 = 9
      assert.equals(24, layout.board_height)
      assert.equals(9, layout.preview_height)
    end)

    it("enforces minimum board height with preview", function()
      -- Very small terminal with preview
      local layout = Board.calculate_layout(5, 120, 15, 5)
      assert.is_true(layout.board_height >= 5)
    end)

    it("includes header_row and header_height in layout", function()
      local layout = Board.calculate_layout(5, 120, 40)
      assert.is_not_nil(layout.header_row)
      assert.equals(1, layout.header_height)
      -- header_row should be before start_row
      assert.is_true(layout.header_row < layout.start_row)
      -- start_row = header_row + 4 (header_inner + border + gap)
      assert.equals(layout.header_row + 4, layout.start_row)
    end)

    it("includes header_row in preview layout", function()
      local layout = Board.calculate_layout(5, 120, 40, 8)
      assert.is_not_nil(layout.header_row)
      assert.equals(1, layout.header_height)
      assert.equals(layout.header_row + 4, layout.start_row)
    end)
  end)
end)

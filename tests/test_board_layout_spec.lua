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
      assert.equals(32, layout.board_height) -- floor(40 * 0.8)
      -- col_width = floor((108 - 4*1) / 5) = floor(104/5) = 20
      assert.equals(20, layout.col_width)
      assert.equals(1, layout.gap)
    end)

    it("calculates correct dimensions for 6 columns on 160x50 terminal", function()
      local layout = Board.calculate_layout(6, 160, 50)
      assert.equals(144, layout.board_width) -- floor(160 * 0.9)
      assert.equals(40, layout.board_height) -- floor(50 * 0.8)
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
      -- start_row = floor((40 - 32) / 2) = 4
      assert.equals(4, layout.start_row)
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
      -- available = floor(40*0.8) - 3 = 29
      -- board = floor(29 * 0.75) = 21, preview = 29 - 21 = 8
      assert.equals(21, layout.board_height)
      assert.equals(8, layout.preview_height)
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
      -- available = floor(50*0.8) - 3 = 37
      -- board = floor(37 * 0.75) = 27, preview = 37 - 27 = 10
      assert.equals(27, layout.board_height)
      assert.equals(10, layout.preview_height)
    end)

    it("enforces minimum board height with preview", function()
      -- Very small terminal with preview
      local layout = Board.calculate_layout(5, 120, 15, 5)
      assert.is_true(layout.board_height >= 5)
    end)
  end)
end)

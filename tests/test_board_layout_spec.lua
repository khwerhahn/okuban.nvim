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
  end)
end)

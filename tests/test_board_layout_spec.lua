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
      -- board_height = floor((floor(40*0.8) - 4) * 0.8) = floor(28 * 0.8) = 22
      assert.equals(22, layout.board_height)
      -- col_width = floor((108 - 4*1) / 5) = floor(104/5) = 20
      assert.equals(20, layout.col_width)
      assert.equals(1, layout.gap)
    end)

    it("calculates correct dimensions for 6 columns on 160x50 terminal", function()
      local layout = Board.calculate_layout(6, 160, 50)
      assert.equals(144, layout.board_width) -- floor(160 * 0.9)
      -- board_height = floor((floor(50*0.8) - 4) * 0.8) = floor(36 * 0.8) = 28
      assert.equals(28, layout.board_height)
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
      -- total_visual = 3 (header) + 1 (gap) + 22 + 2 (border) = 28
      -- block_start = floor((40 - 28) / 2) = 6
      -- start_row = block_start + 4 (header space) = 10
      assert.equals(10, layout.start_row)
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
      -- board = floor(floor(25 * 0.75) * 0.8) = floor(18 * 0.8) = 14
      -- preview = 25 - 14 = 11
      assert.equals(14, layout.board_height)
      assert.equals(11, layout.preview_height)
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
      -- board = floor(floor(33 * 0.75) * 0.8) = floor(24 * 0.8) = 19
      -- preview = 33 - 19 = 14
      assert.equals(19, layout.board_height)
      assert.equals(14, layout.preview_height)
    end)

    it("enforces minimum board height with preview", function()
      -- Very small terminal with preview
      local layout = Board.calculate_layout(5, 120, 15, 5)
      assert.is_true(layout.board_height >= 5)
    end)

    it("enforces minimum board height without preview", function()
      -- Very small terminal without preview
      local layout = Board.calculate_layout(5, 30, 10)
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

    it("has no logo_row when show_logo is false", function()
      local layout = Board.calculate_layout(5, 120, 40, 0, false)
      assert.is_nil(layout.logo_row)
    end)

    it("has no logo_row when show_logo is nil", function()
      local layout = Board.calculate_layout(5, 120, 40)
      assert.is_nil(layout.logo_row)
    end)

    it("includes logo_row when show_logo is true", function()
      local layout = Board.calculate_layout(5, 120, 40, 0, true)
      assert.is_not_nil(layout.logo_row)
      -- logo_row should be above header_row
      assert.is_true(layout.logo_row < layout.header_row)
      -- header_row = logo_row + 6 (canopy height)
      assert.equals(layout.logo_row + 6, layout.header_row)
    end)

    it("reduces board_height when logo is shown", function()
      local without = Board.calculate_layout(5, 120, 40, 0, false)
      local with_logo = Board.calculate_layout(5, 120, 40, 0, true)
      -- Logo takes 6 rows from available space, reducing board_height
      assert.is_true(with_logo.board_height < without.board_height)
    end)

    it("shifts header_row down by logo height", function()
      local without = Board.calculate_layout(5, 120, 40, 0, false)
      local with_logo = Board.calculate_layout(5, 120, 40, 0, true)
      -- header_row with logo should be shifted compared to without
      -- (exact difference depends on centering, but logo_row + 6 == header_row)
      assert.equals(with_logo.logo_row + 6, with_logo.header_row)
      -- start_row = header_row + 4 in both cases
      assert.equals(with_logo.header_row + 4, with_logo.start_row)
      assert.equals(without.header_row + 4, without.start_row)
    end)

    it("includes logo_row with preview and logo", function()
      local layout = Board.calculate_layout(5, 120, 40, 8, true)
      assert.is_not_nil(layout.logo_row)
      assert.is_not_nil(layout.preview_row)
      assert.is_true(layout.logo_row < layout.header_row)
      assert.equals(layout.logo_row + 6, layout.header_row)
    end)

    it("reduces board_height with preview when logo is shown", function()
      local without = Board.calculate_layout(5, 120, 40, 8, false)
      local with_logo = Board.calculate_layout(5, 120, 40, 8, true)
      assert.is_true(with_logo.board_height < without.board_height)
    end)
  end)

  describe("compute_column_widths", function()
    it("returns equal widths when no focus column", function()
      -- 5 columns, 108 board width, gap 1
      -- available = 108 - 4*1 = 104, base = floor(104/5) = 20
      local widths = Board.compute_column_widths(5, 108, 1, nil)
      assert.equals(5, #widths)
      for _, w in ipairs(widths) do
        assert.equals(20, w)
      end
    end)

    it("returns equal widths for single column", function()
      local widths = Board.compute_column_widths(1, 108, 1, 1)
      assert.equals(1, #widths)
      assert.equals(108, widths[1])
    end)

    it("expands focused column with default 1.8x multiplier", function()
      -- 5 columns, 108 board width, gap 1
      -- available = 104, base = 20
      -- expanded = floor(20 * 1.8) = 36
      -- shrunk = floor((104 - 36) / 4) = floor(68/4) = 17 — BUT 17 < 20 (min_width)
      -- min_width enforced: shrunk = 20, expanded = 104 - 20*4 = 24
      local widths = Board.compute_column_widths(5, 108, 1, 3)
      assert.equals(5, #widths)
      -- Focus column (3) should be larger than others
      assert.is_true(widths[3] > widths[1])
      -- Non-focus columns should be >= 20 (min_width)
      for i, w in ipairs(widths) do
        if i ~= 3 then
          assert.is_true(w >= 20, "Column " .. i .. " width " .. w .. " < 20")
        end
      end
    end)

    it("expands correctly with wider board", function()
      -- 5 columns, 160 board width, gap 1
      -- available = 156, base = floor(156/5) = 31
      -- expanded = floor(31 * 1.8) = 55
      -- shrunk = floor((156 - 55) / 4) = floor(101/4) = 25
      -- 25 >= 20, so no min_width enforcement
      local widths = Board.compute_column_widths(5, 160, 1, 2)
      assert.equals(5, #widths)
      assert.equals(55, widths[2])
      assert.equals(25, widths[1])
      assert.equals(25, widths[3])
    end)

    it("uses custom multiplier", function()
      -- 5 columns, 160 board width, gap 1, multiplier 2.5
      -- available = 156, base = 31
      -- expanded = floor(31 * 2.5) = 77
      -- shrunk = floor((156 - 77) / 4) = floor(79/4) = 19 — below 20!
      -- min_width enforced: shrunk = 20, expanded = 156 - 20*4 = 76
      local widths = Board.compute_column_widths(5, 160, 1, 1, 2.5)
      assert.equals(5, #widths)
      assert.equals(76, widths[1])
      for i = 2, 5 do
        assert.equals(20, widths[i])
      end
    end)

    it("falls back to equal widths when expansion is impossible", function()
      -- Very narrow: all columns already at minimum
      -- 5 columns, 104 board width (100 available), gap 1
      -- base = floor(100/5) = 20
      -- expanded = floor(20 * 1.8) = 36
      -- shrunk = floor((100 - 36) / 4) = 16 — below 20
      -- min_width enforced: shrunk = 20, expanded = 100 - 80 = 20
      -- expanded <= base (20 <= 20), so fall back to equal
      local widths = Board.compute_column_widths(5, 104, 1, 3)
      assert.equals(5, #widths)
      for _, w in ipairs(widths) do
        assert.equals(20, w)
      end
    end)

    it("handles first column focus", function()
      local widths = Board.compute_column_widths(5, 160, 1, 1)
      -- Focus on column 1
      assert.is_true(widths[1] > widths[2])
    end)

    it("handles last column focus", function()
      local widths = Board.compute_column_widths(5, 160, 1, 5)
      assert.is_true(widths[5] > widths[4])
    end)

    it("total widths plus gaps equal board_width or less", function()
      local board_width = 160
      local gap = 1
      local num_cols = 5
      local widths = Board.compute_column_widths(num_cols, board_width, gap, 3)
      local total = 0
      for _, w in ipairs(widths) do
        total = total + w
      end
      total = total + (num_cols - 1) * gap
      assert.is_true(total <= board_width)
    end)
  end)
end)

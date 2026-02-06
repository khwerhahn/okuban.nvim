describe("okuban.ui.card", function()
  local card_mod

  before_each(function()
    package.loaded["okuban.ui.card"] = nil
    card_mod = require("okuban.ui.card")
  end)

  describe("render_card", function()
    it("formats issue as #number title", function()
      local line = card_mod.render_card({ number = 42, title = "Add board rendering" }, 40)
      assert.equals("#42 Add board rendering", line)
    end)

    it("truncates long titles with ellipsis", function()
      local line = card_mod.render_card({ number = 1, title = "This is a very long title that exceeds" }, 20)
      -- prefix "#1 " = 3 chars, available = 17, title truncated to 14 + "..." = 17
      assert.equals("#1 This is a very...", line)
      assert.is_true(#line <= 20)
    end)

    it("handles single-digit issue numbers", function()
      local line = card_mod.render_card({ number = 5, title = "Short" }, 30)
      assert.equals("#5 Short", line)
    end)

    it("handles large issue numbers", function()
      local line = card_mod.render_card({ number = 12345, title = "Big number" }, 40)
      assert.equals("#12345 Big number", line)
    end)

    it("handles missing title", function()
      local line = card_mod.render_card({ number = 1 }, 20)
      assert.equals("#1 ", line)
    end)

    it("handles exact-fit title", function()
      local line = card_mod.render_card({ number = 1, title = "12345678901234567" }, 20)
      -- prefix "#1 " = 3 chars, available = 17, title fits exactly
      assert.equals("#1 12345678901234567", line)
    end)
  end)

  describe("render_column", function()
    it("renders all cards", function()
      local issues = {
        { number = 1, title = "First" },
        { number = 2, title = "Second" },
      }
      local lines = card_mod.render_column(issues, 30)
      assert.equals(2, #lines)
      assert.equals("#1 First", lines[1])
      assert.equals("#2 Second", lines[2])
    end)

    it("shows placeholder for empty column", function()
      local lines = card_mod.render_column({}, 30)
      assert.equals(1, #lines)
      assert.equals("  (no issues)", lines[1])
    end)
  end)
end)

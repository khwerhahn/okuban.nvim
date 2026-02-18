describe("okuban.ui.tree", function()
  local tree

  before_each(function()
    package.loaded["okuban.ui.tree"] = nil
    tree = require("okuban.ui.tree")
  end)

  describe("state management", function()
    it("is_expanded returns false initially", function()
      assert.is_false(tree.is_expanded(1, 42))
    end)

    it("set_expanded marks parent as expanded", function()
      tree.set_expanded(1, 42, { { number = 1, title = "Sub", state = "OPEN" } })
      assert.is_true(tree.is_expanded(1, 42))
      assert.is_false(tree.is_loading(1, 42))
    end)

    it("set_loading marks parent as loading", function()
      tree.set_loading(1, 42)
      assert.is_true(tree.is_expanded(1, 42))
      assert.is_true(tree.is_loading(1, 42))
    end)

    it("collapse removes expansion for one parent", function()
      tree.set_expanded(1, 42, { { number = 1, title = "Sub", state = "OPEN" } })
      tree.set_expanded(1, 43, { { number = 2, title = "Sub2", state = "OPEN" } })
      tree.collapse(1, 42)
      assert.is_false(tree.is_expanded(1, 42))
      assert.is_true(tree.is_expanded(1, 43))
    end)

    it("collapse_all removes all expansions in a column", function()
      tree.set_expanded(1, 42, { { number = 1, title = "Sub", state = "OPEN" } })
      tree.set_expanded(1, 43, { { number = 2, title = "Sub2", state = "OPEN" } })
      tree.collapse_all(1)
      assert.is_false(tree.is_expanded(1, 42))
      assert.is_false(tree.is_expanded(1, 43))
    end)

    it("has_any_expanded returns true when column has expansions", function()
      tree.set_expanded(1, 42, { { number = 1, title = "Sub", state = "OPEN" } })
      assert.is_true(tree.has_any_expanded(1))
    end)

    it("has_any_expanded returns false for empty column", function()
      assert.is_false(tree.has_any_expanded(1))
    end)

    it("has_any_expanded returns false after collapse_all", function()
      tree.set_expanded(1, 42, { { number = 1, title = "Sub", state = "OPEN" } })
      tree.collapse_all(1)
      assert.is_false(tree.has_any_expanded(1))
    end)

    it("reset clears expansion state but preserves cache", function()
      tree.set_expanded(1, 42, { { number = 1, title = "Sub", state = "OPEN" } })
      tree.reset()
      assert.is_false(tree.is_expanded(1, 42))
      -- Cache survives reset
      local cached = tree.get_cached(42)
      assert.is_not_nil(cached)
      assert.equals(1, #cached)
    end)

    it("get_cached returns nil for unknown parent", function()
      assert.is_nil(tree.get_cached(999))
    end)

    it("set_expanded populates cache", function()
      local subs = { { number = 10, title = "A", state = "OPEN" } }
      tree.set_expanded(1, 50, subs)
      local cached = tree.get_cached(50)
      assert.is_not_nil(cached)
      assert.equals(1, #cached)
      assert.equals(10, cached[1].number)
    end)
  end)

  describe("build_visible_items", function()
    it("returns card-only items when nothing expanded", function()
      local col = {
        issues = {
          { number = 1, title = "A" },
          { number = 2, title = "B" },
        },
      }
      local items = tree.build_visible_items(col, 1)
      assert.equals(2, #items)
      assert.equals("card", items[1].type)
      assert.equals(1, items[1].card_idx)
      assert.equals("card", items[2].type)
      assert.equals(2, items[2].card_idx)
    end)

    it("interleaves sub-issues when expanded", function()
      local col = {
        issues = {
          { number = 10, title = "Parent" },
          { number = 20, title = "Other" },
        },
      }
      tree.set_expanded(1, 10, {
        { number = 11, title = "Sub1", state = "OPEN" },
        { number = 12, title = "Sub2", state = "CLOSED" },
      })
      local items = tree.build_visible_items(col, 1)
      assert.equals(4, #items)
      assert.equals("card", items[1].type)
      assert.equals("sub_issue", items[2].type)
      assert.equals(11, items[2].sub.number)
      assert.is_false(items[2].is_last)
      assert.equals("sub_issue", items[3].type)
      assert.equals(12, items[3].sub.number)
      assert.is_true(items[3].is_last)
      assert.equals("card", items[4].type)
    end)

    it("includes loading placeholder", function()
      local col = {
        issues = { { number = 10, title = "Parent" } },
      }
      tree.set_loading(1, 10)
      local items = tree.build_visible_items(col, 1)
      assert.equals(2, #items)
      assert.equals("card", items[1].type)
      assert.equals("loading", items[2].type)
    end)
  end)

  describe("render_sub_issue_line", function()
    it("uses tree connector for non-last item", function()
      local line = tree.render_sub_issue_line({ number = 14, title = "Layout", state = "OPEN" }, false, 40)
      -- Should contain the box-drawing connector character (U+251C)
      assert.truthy(line:find("\xe2\x94\x9c"))
      assert.truthy(line:find("#14"))
      assert.truthy(line:find("Layout"))
    end)

    it("uses corner connector for last item", function()
      local line = tree.render_sub_issue_line({ number = 16, title = "Done", state = "CLOSED" }, true, 40)
      -- Should contain the box-drawing corner character (U+2514)
      assert.truthy(line:find("\xe2\x94\x94"))
      assert.truthy(line:find("#16"))
      -- Should contain check mark for closed state
      assert.truthy(line:find("\xe2\x9c\x93"))
    end)

    it("uses open circle for open state", function()
      local line = tree.render_sub_issue_line({ number = 14, title = "Open", state = "OPEN" }, false, 40)
      assert.truthy(line:find("\xe2\x97\x8b"))
    end)

    it("truncates long titles with correct display width", function()
      local long_title = string.rep("A", 100)
      -- width=30, issue #1: prefix display = 7 + 1 = 8, avail = 22
      -- Title should be truncated to 21 chars + ellipsis
      local line = tree.render_sub_issue_line({ number = 1, title = long_title, state = "OPEN" }, true, 30)
      assert.truthy(line:find("\xe2\x80\xa6")) -- contains ellipsis
      -- Title portion should fit within available space
      assert.truthy(line:find("#1"))
    end)

    it("handles nil title gracefully", function()
      local line = tree.render_sub_issue_line({ number = 5, state = "OPEN" }, false, 40)
      assert.truthy(line:find("#5"))
    end)
  end)

  describe("render_loading_line", function()
    it("contains loading text", function()
      local line = tree.render_loading_line(40)
      assert.truthy(line:find("loading"))
    end)
  end)
end)

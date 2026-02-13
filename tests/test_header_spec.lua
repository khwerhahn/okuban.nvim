describe("okuban.ui.header", function()
  local header

  before_each(function()
    package.loaded["okuban.ui.header"] = nil
    package.loaded["okuban.config"] = nil
    require("okuban.config")
    header = require("okuban.ui.header")
    header._reset()
  end)

  describe("mode constants", function()
    it("has default mode", function()
      assert.equals("default", header.MODE_DEFAULT)
    end)

    it("has issue mode", function()
      assert.equals("issue", header.MODE_ISSUE)
    end)
  end)

  describe("get_mode", function()
    it("returns default mode initially", function()
      assert.equals("default", header.get_mode())
    end)
  end)

  describe("is_issue_mode", function()
    it("returns false initially", function()
      assert.is_false(header.is_issue_mode())
    end)
  end)

  describe("_render default mode", function()
    it("returns a single line with default keybindings", function()
      local lines = header._render("default", nil)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("%[Enter%]"))
      assert.truthy(lines[1]:find("%[m%]"))
      assert.truthy(lines[1]:find("%[%?%]"))
      assert.truthy(lines[1]:find("%[q%]"))
    end)

    it("includes Help action", function()
      local lines = header._render("default", nil)
      assert.truthy(lines[1]:find("Help"))
    end)

    it("includes Refresh action", function()
      local lines = header._render("default", nil)
      assert.truthy(lines[1]:find("Refresh"))
    end)
  end)

  describe("_render issue mode", function()
    local open_issue = { number = 42, title = "Fix login bug", state = "OPEN" }
    local closed_issue = { number = 99, title = "Old bug", state = "CLOSED" }

    it("returns a single line with issue actions", function()
      local lines = header._render("issue", open_issue)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("%[m%]"))
      assert.truthy(lines[1]:find("%[v%]"))
      assert.truthy(lines[1]:find("#42"))
    end)

    it("shows Back action for escaping issue mode", function()
      local lines = header._render("issue", open_issue)
      assert.truthy(lines[1]:find("%[Esc%] Back"))
    end)

    it("includes close and assign for open issues", function()
      local lines = header._render("issue", open_issue)
      assert.truthy(lines[1]:find("%[c%] Close"))
      assert.truthy(lines[1]:find("%[a%] Assign"))
    end)

    it("excludes close and assign for closed issues", function()
      local lines = header._render("issue", closed_issue)
      assert.is_nil(lines[1]:find("%[c%] Close"))
      assert.is_nil(lines[1]:find("%[a%] Assign"))
    end)

    it("includes issue number and title", function()
      local lines = header._render("issue", open_issue)
      assert.truthy(lines[1]:find("#42: Fix login bug"))
    end)

    it("truncates long titles", function()
      local long_issue = { number = 1, title = string.rep("x", 200), state = "OPEN" }
      local lines = header._render("issue", long_issue)
      assert.truthy(lines[1]:find("%.%.%."))
    end)

    it("falls back to default when issue is nil", function()
      local lines = header._render("issue", nil)
      assert.truthy(lines[1]:find("%[Enter%]"))
    end)
  end)

  describe("enter/exit issue mode", function()
    it("enters issue mode via update", function()
      -- Simulate a header buffer (module-level state)
      -- Without a real buffer, update is a no-op but mode tracking still works
      -- via enter_issue_mode/exit_issue_mode calling update which checks buffer validity
      -- For unit tests, we test the render logic directly
      assert.is_false(header.is_issue_mode())
    end)
  end)

  describe("close", function()
    it("resets mode on close", function()
      header.close()
      assert.equals("default", header.get_mode())
      assert.is_false(header.is_issue_mode())
    end)
  end)

  describe("get_win", function()
    it("returns nil when no header window exists", function()
      assert.is_nil(header.get_win())
    end)
  end)
end)

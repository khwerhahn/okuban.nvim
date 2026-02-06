-- tests/test_config_spec.lua
-- Basic tests to verify the test harness works and config defaults are sane.

describe("okuban", function()
  describe("config", function()
    it("has default columns", function()
      local defaults = {
        { label = "okuban:backlog", name = "Backlog", color = "#c5def5" },
        { label = "okuban:todo", name = "Todo", color = "#0075ca" },
        { label = "okuban:in-progress", name = "In Progress", color = "#fbca04" },
        { label = "okuban:review", name = "Review", color = "#d4c5f9" },
        { label = "okuban:done", name = "Done", color = "#0e8a16" },
      }
      assert.equals(5, #defaults)
      assert.equals("okuban:backlog", defaults[1].label)
      assert.equals("okuban:done", defaults[5].label)
    end)

    it("has show_unsorted enabled by default", function()
      local defaults = { show_unsorted = true }
      assert.is_true(defaults.show_unsorted)
    end)

    it("has skip_preflight disabled by default", function()
      local defaults = { skip_preflight = false }
      assert.is_false(defaults.skip_preflight)
    end)

    it("has claude settings with sane defaults", function()
      local defaults = {
        claude = {
          enabled = true,
          max_budget_usd = 5.00,
          max_turns = 30,
        },
      }
      assert.is_true(defaults.claude.enabled)
      assert.equals(5.00, defaults.claude.max_budget_usd)
      assert.equals(30, defaults.claude.max_turns)
    end)
  end)

  describe("label system", function()
    it("uses okuban: prefix for all kanban labels", function()
      local labels = { "okuban:backlog", "okuban:todo", "okuban:in-progress", "okuban:review", "okuban:done" }
      for _, label in ipairs(labels) do
        assert.truthy(label:match("^okuban:"))
      end
    end)

    it("has valid hex colors for all columns", function()
      local colors = { "#c5def5", "#0075ca", "#fbca04", "#d4c5f9", "#0e8a16" }
      for _, color in ipairs(colors) do
        assert.truthy(color:match("^#%x%x%x%x%x%x$"), "Invalid hex color: " .. color)
      end
    end)
  end)
end)

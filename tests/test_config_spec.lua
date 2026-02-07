describe("okuban.config", function()
  local config

  before_each(function()
    package.loaded["okuban.config"] = nil
    config = require("okuban.config")
  end)

  describe("defaults", function()
    it("has 5 kanban columns", function()
      local cfg = config.get()
      assert.equals(5, #cfg.columns)
    end)

    it("has correct column labels", function()
      local cfg = config.get()
      assert.equals("okuban:backlog", cfg.columns[1].label)
      assert.equals("okuban:todo", cfg.columns[2].label)
      assert.equals("okuban:in-progress", cfg.columns[3].label)
      assert.equals("okuban:review", cfg.columns[4].label)
      assert.equals("okuban:done", cfg.columns[5].label)
    end)

    it("has correct column names", function()
      local cfg = config.get()
      assert.equals("Backlog", cfg.columns[1].name)
      assert.equals("In Progress", cfg.columns[3].name)
      assert.equals("Done", cfg.columns[5].name)
    end)

    it("has valid hex colors for all columns", function()
      local cfg = config.get()
      for _, col in ipairs(cfg.columns) do
        assert.truthy(col.color:match("^#%x%x%x%x%x%x$"), "Invalid hex color: " .. col.color)
      end
    end)

    it("uses okuban: prefix for all kanban labels", function()
      local cfg = config.get()
      for _, col in ipairs(cfg.columns) do
        assert.truthy(col.label:match("^okuban:"), "Missing prefix: " .. col.label)
      end
    end)

    it("has limit on Done column", function()
      local cfg = config.get()
      assert.equals(20, cfg.columns[5].limit)
    end)

    it("has no limit on other columns", function()
      local cfg = config.get()
      assert.is_nil(cfg.columns[1].limit)
      assert.is_nil(cfg.columns[2].limit)
      assert.is_nil(cfg.columns[3].limit)
      assert.is_nil(cfg.columns[4].limit)
    end)

    it("has preview_lines default of 8", function()
      assert.equals(8, config.get().preview_lines)
    end)

    it("has show_tldr enabled by default", function()
      assert.is_true(config.get().show_tldr)
    end)

    it("has poll_interval default of 20", function()
      assert.equals(20, config.get().poll_interval)
    end)

    it("has show_unsorted enabled", function()
      assert.is_true(config.get().show_unsorted)
    end)

    it("has skip_preflight disabled", function()
      assert.is_false(config.get().skip_preflight)
    end)

    it("has nil github_hostname", function()
      assert.is_nil(config.get().github_hostname)
    end)

    it("has source default of labels", function()
      assert.equals("labels", config.get().source)
    end)

    it("has project defaults", function()
      local proj = config.get().project
      assert.is_nil(proj.number)
      assert.is_nil(proj.owner)
      assert.equals(20, proj.done_limit)
    end)

    it("has claude settings with sane defaults", function()
      local claude = config.get().claude
      assert.is_true(claude.enabled)
      assert.equals(5.00, claude.max_budget_usd)
      assert.equals(30, claude.max_turns)
    end)

    it("has default keymaps", function()
      local keymaps = config.get().keymaps
      assert.equals("h", keymaps.column_left)
      assert.equals("l", keymaps.column_right)
      assert.equals("k", keymaps.card_up)
      assert.equals("j", keymaps.card_down)
      assert.equals("m", keymaps.move_card)
      assert.equals("<CR>", keymaps.open_actions)
      assert.equals("g", keymaps.goto_current)
      assert.equals("q", keymaps.close)
      assert.equals("r", keymaps.refresh)
      assert.equals("?", keymaps.help)
    end)
  end)

  describe("setup", function()
    it("merges user overrides", function()
      config.setup({ show_unsorted = false })
      assert.is_false(config.get().show_unsorted)
    end)

    it("preserves defaults for unset keys", function()
      config.setup({ show_unsorted = false })
      assert.equals(5, #config.get().columns)
      assert.is_true(config.get().claude.enabled)
    end)

    it("deep merges nested tables", function()
      config.setup({ claude = { max_turns = 50 } })
      local claude = config.get().claude
      assert.equals(50, claude.max_turns)
      assert.equals(5.00, claude.max_budget_usd)
      assert.is_true(claude.enabled)
    end)

    it("allows keymap overrides", function()
      config.setup({ keymaps = { close = "<Esc>" } })
      local keymaps = config.get().keymaps
      assert.equals("<Esc>", keymaps.close)
      assert.equals("h", keymaps.column_left)
    end)

    it("allows source and project overrides", function()
      config.setup({ source = "project", project = { number = 1, owner = "myorg" } })
      assert.equals("project", config.get().source)
      assert.equals(1, config.get().project.number)
      assert.equals("myorg", config.get().project.owner)
      assert.equals(20, config.get().project.done_limit)
    end)

    it("resets to defaults on each setup call", function()
      config.setup({ show_unsorted = false })
      assert.is_false(config.get().show_unsorted)
      config.setup({})
      assert.is_true(config.get().show_unsorted)
    end)
  end)

  describe("defaults()", function()
    it("returns a copy that does not mutate internal state", function()
      local d = config.defaults()
      d.show_unsorted = false
      assert.is_true(config.get().show_unsorted)
    end)
  end)
end)

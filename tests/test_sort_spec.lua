describe("okuban.sort", function()
  local config, api_labels, api_project

  before_each(function()
    package.loaded["okuban.config"] = nil
    package.loaded["okuban.api_labels"] = nil
    package.loaded["okuban.api_project"] = nil
    config = require("okuban.config")
    api_labels = require("okuban.api_labels")
    api_project = require("okuban.api_project")
  end)

  -- ---------------------------------------------------------------------------
  -- Config defaults
  -- ---------------------------------------------------------------------------

  describe("config", function()
    it("has sort defaults", function()
      local cfg = config.get()
      assert.is_not_nil(cfg.sort)
      assert.equals("updated", cfg.sort.field)
      assert.equals("desc", cfg.sort.order)
    end)

    it("allows sort field override", function()
      config.setup({ sort = { field = "created" } })
      assert.equals("created", config.get().sort.field)
      assert.equals("desc", config.get().sort.order) -- preserved
    end)

    it("allows sort order override", function()
      config.setup({ sort = { order = "asc" } })
      assert.equals("updated", config.get().sort.field) -- preserved
      assert.equals("asc", config.get().sort.order)
    end)

    it("allows both sort overrides", function()
      config.setup({ sort = { field = "number", order = "asc" } })
      assert.equals("number", config.get().sort.field)
      assert.equals("asc", config.get().sort.order)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- sort_issues (Lua-side sorting)
  -- ---------------------------------------------------------------------------

  describe("sort_issues", function()
    it("sorts by updatedAt descending by default", function()
      local issues = {
        { number = 1, updatedAt = "2025-01-01T00:00:00Z", createdAt = "2024-01-01T00:00:00Z" },
        { number = 2, updatedAt = "2025-06-01T00:00:00Z", createdAt = "2024-06-01T00:00:00Z" },
        { number = 3, updatedAt = "2025-03-01T00:00:00Z", createdAt = "2024-03-01T00:00:00Z" },
      }
      api_labels.sort_issues(issues)
      assert.equals(2, issues[1].number)
      assert.equals(3, issues[2].number)
      assert.equals(1, issues[3].number)
    end)

    it("sorts by updatedAt ascending", function()
      config.setup({ sort = { field = "updated", order = "asc" } })
      local issues = {
        { number = 1, updatedAt = "2025-06-01T00:00:00Z" },
        { number = 2, updatedAt = "2025-01-01T00:00:00Z" },
        { number = 3, updatedAt = "2025-03-01T00:00:00Z" },
      }
      api_labels.sort_issues(issues)
      assert.equals(2, issues[1].number)
      assert.equals(3, issues[2].number)
      assert.equals(1, issues[3].number)
    end)

    it("sorts by createdAt descending", function()
      config.setup({ sort = { field = "created", order = "desc" } })
      local issues = {
        { number = 1, createdAt = "2024-01-01T00:00:00Z" },
        { number = 2, createdAt = "2024-06-01T00:00:00Z" },
        { number = 3, createdAt = "2024-03-01T00:00:00Z" },
      }
      api_labels.sort_issues(issues)
      assert.equals(2, issues[1].number)
      assert.equals(3, issues[2].number)
      assert.equals(1, issues[3].number)
    end)

    it("sorts by number descending", function()
      config.setup({ sort = { field = "number", order = "desc" } })
      local issues = {
        { number = 5 },
        { number = 10 },
        { number = 1 },
      }
      api_labels.sort_issues(issues)
      assert.equals(10, issues[1].number)
      assert.equals(5, issues[2].number)
      assert.equals(1, issues[3].number)
    end)

    it("sorts by number ascending", function()
      config.setup({ sort = { field = "number", order = "asc" } })
      local issues = {
        { number = 5 },
        { number = 10 },
        { number = 1 },
      }
      api_labels.sort_issues(issues)
      assert.equals(1, issues[1].number)
      assert.equals(5, issues[2].number)
      assert.equals(10, issues[3].number)
    end)

    it("handles missing date fields gracefully", function()
      local issues = {
        { number = 1 },
        { number = 2, updatedAt = "2025-06-01T00:00:00Z" },
        { number = 3 },
      }
      -- Should not error
      api_labels.sort_issues(issues)
      -- Issue with date should be first (desc, non-empty > empty)
      assert.equals(2, issues[1].number)
    end)

    it("handles empty list", function()
      local issues = {}
      api_labels.sort_issues(issues)
      assert.equals(0, #issues)
    end)

    it("handles single item", function()
      local issues = { { number = 1, updatedAt = "2025-01-01T00:00:00Z" } }
      api_labels.sort_issues(issues)
      assert.equals(1, issues[1].number)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Project mode: build_board_data applies sort
  -- ---------------------------------------------------------------------------

  describe("project build_board_data sort", function()
    local status_field = {
      id = "field1",
      options = {
        { id = "opt1", name = "Todo" },
        { id = "opt2", name = "In Progress" },
      },
    }

    it("sorts project items by updatedAt descending", function()
      local items = {
        {
          id = "item1",
          fieldValueByName = { name = "Todo", optionId = "opt1" },
          content = {
            number = 1,
            title = "Old",
            state = "OPEN",
            updatedAt = "2025-01-01T00:00:00Z",
            createdAt = "2024-01-01T00:00:00Z",
          },
        },
        {
          id = "item2",
          fieldValueByName = { name = "Todo", optionId = "opt1" },
          content = {
            number = 2,
            title = "New",
            state = "OPEN",
            updatedAt = "2025-06-01T00:00:00Z",
            createdAt = "2024-06-01T00:00:00Z",
          },
        },
      }

      local board_data = api_project.build_board_data(items, status_field, false, 20)
      local todo_col = board_data.columns[1]
      assert.equals(2, #todo_col.issues)
      -- Newest updated first (desc)
      assert.equals(2, todo_col.issues[1].number)
      assert.equals(1, todo_col.issues[2].number)
    end)

    it("sorts project items by created ascending", function()
      config.setup({ sort = { field = "created", order = "asc" } })
      local items = {
        {
          id = "item1",
          fieldValueByName = { name = "Todo", optionId = "opt1" },
          content = {
            number = 1,
            title = "First",
            state = "OPEN",
            createdAt = "2024-06-01T00:00:00Z",
            updatedAt = "2025-01-01T00:00:00Z",
          },
        },
        {
          id = "item2",
          fieldValueByName = { name = "Todo", optionId = "opt1" },
          content = {
            number = 2,
            title = "Second",
            state = "OPEN",
            createdAt = "2024-01-01T00:00:00Z",
            updatedAt = "2025-06-01T00:00:00Z",
          },
        },
      }

      local board_data = api_project.build_board_data(items, status_field, false, 20)
      local todo_col = board_data.columns[1]
      -- Oldest created first (asc)
      assert.equals(2, todo_col.issues[1].number)
      assert.equals(1, todo_col.issues[2].number)
    end)

    it("sorts unsorted items in project mode", function()
      local items = {
        {
          id = "item1",
          fieldValueByName = {},
          content = {
            number = 1,
            title = "Old unsorted",
            state = "OPEN",
            updatedAt = "2025-01-01T00:00:00Z",
          },
        },
        {
          id = "item2",
          fieldValueByName = {},
          content = {
            number = 2,
            title = "New unsorted",
            state = "OPEN",
            updatedAt = "2025-06-01T00:00:00Z",
          },
        },
      }

      local board_data = api_project.build_board_data(items, status_field, true, 20)
      assert.equals(2, #board_data.unsorted)
      -- Newest updated first (desc default)
      assert.equals(2, board_data.unsorted[1].number)
      assert.equals(1, board_data.unsorted[2].number)
    end)
  end)
end)

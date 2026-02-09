local helpers = require("tests.helpers")

describe("okuban.api_project", function()
  local api_project, config

  before_each(function()
    package.loaded["okuban.api_project"] = nil
    package.loaded["okuban.api"] = nil
    package.loaded["okuban.api_labels"] = nil
    package.loaded["okuban.config"] = nil
    config = require("okuban.config")
    require("okuban.api")
    api_project = require("okuban.api_project")
    api_project.reset_cache()
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("detect_owner", function()
    it("returns owner login from repo view", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "khwerhahn\n" },
      })

      local done = false
      local result = nil
      api_project.detect_owner(function(owner)
        done = true
        result = owner
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals("khwerhahn", result)
    end)

    it("returns nil on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "not a git repo" },
      })

      local done = false
      local result = "not_nil"
      api_project.detect_owner(function(owner)
        done = true
        result = owner
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_nil(result)
    end)
  end)

  describe("list_projects", function()
    it("parses project list response", function()
      local json = vim.json.encode({
        projects = {
          { number = 1, title = "Kanban Board", closed = false },
          { number = 2, title = "Sprint Planning", closed = false },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api_project.list_projects("khwerhahn", function(projects)
        done = true
        result = projects
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals(2, #result)
      assert.equals("Kanban Board", result[1].title)
      assert.equals(2, result[2].number)
    end)

    it("returns error on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "scope error" },
      })

      local done = false
      local result_err = nil
      api_project.list_projects("khwerhahn", function(_, err)
        done = true
        result_err = err
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.truthy(result_err)
      assert.truthy(result_err:match("Failed to list projects"))
    end)
  end)

  describe("resolve_project_id", function()
    it("returns project node ID", function()
      local json = vim.json.encode({
        id = "PVT_kwHOABaups4BDqWe",
        title = "Kanban",
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api_project.resolve_project_id(1, "khwerhahn", function(project_id)
        done = true
        result = project_id
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals("PVT_kwHOABaups4BDqWe", result)
    end)
  end)

  describe("detect_column_field", function()
    it("detects Workflow Stage from Board view", function()
      local json = vim.json.encode({
        data = {
          node = {
            views = {
              nodes = {
                {
                  layout = "TABLE_LAYOUT",
                  verticalGroupByFields = { nodes = {} },
                },
                {
                  layout = "BOARD_LAYOUT",
                  verticalGroupByFields = {
                    nodes = {
                      { name = "Workflow Stage" },
                    },
                  },
                },
              },
            },
          },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api_project.detect_column_field("PVT_123", function(field_name)
        done = true
        result = field_name
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals("Workflow Stage", result)
      assert.equals("Workflow Stage", api_project.get_cached_column_field_name())
    end)

    it("falls back to Status when no Board view exists", function()
      local json = vim.json.encode({
        data = {
          node = {
            views = {
              nodes = {
                { layout = "TABLE_LAYOUT", verticalGroupByFields = { nodes = {} } },
              },
            },
          },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api_project.detect_column_field("PVT_123", function(field_name)
        done = true
        result = field_name
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals("Status", result)
    end)

    it("falls back to Status on GraphQL error", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "auth error" },
      })

      local done = false
      local result = nil
      api_project.detect_column_field("PVT_123", function(field_name)
        done = true
        result = field_name
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals("Status", result)
    end)

    it("uses cached value on subsequent calls", function()
      api_project._set_cache(nil, nil, "Cached Field")

      local result = nil
      api_project.detect_column_field("PVT_123", function(field_name)
        result = field_name
      end)

      -- Synchronous — no vim.system call needed
      assert.equals("Cached Field", result)
    end)
  end)

  describe("fetch_status_field", function()
    it("extracts Status field with options", function()
      local json = vim.json.encode({
        fields = {
          { name = "Title", id = "FIELD_TITLE" },
          {
            name = "Status",
            id = "PVTSSF_status_123",
            options = {
              { id = "opt_todo", name = "Todo" },
              { id = "opt_doing", name = "In Progress" },
              { id = "opt_done", name = "Done" },
            },
          },
          { name = "Assignees", id = "FIELD_ASSIGNEES" },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api_project.fetch_status_field(1, "khwerhahn", function(field)
        done = true
        result = field
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_not_nil(result)
      assert.equals("PVTSSF_status_123", result.id)
      assert.equals(3, #result.options)
      assert.equals("Todo", result.options[1].name)
      assert.equals("opt_done", result.options[3].id)
    end)

    it("searches for a custom field name", function()
      local json = vim.json.encode({
        fields = {
          { name = "Title", id = "FIELD_TITLE" },
          {
            name = "Workflow Stage",
            id = "PVTSSF_workflow_456",
            options = {
              { id = "opt_inv", name = "Investigation Needed" },
              { id = "opt_ready", name = "Ready" },
            },
          },
          {
            name = "Status",
            id = "PVTSSF_status_123",
            options = { { id = "opt_todo", name = "Todo" } },
          },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result = nil
      api_project.fetch_column_field(1, "khwerhahn", "Workflow Stage", function(field)
        done = true
        result = field
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_not_nil(result)
      assert.equals("PVTSSF_workflow_456", result.id)
      assert.equals(2, #result.options)
      assert.equals("Investigation Needed", result.options[1].name)
    end)

    it("returns error when no Status field exists", function()
      local json = vim.json.encode({
        fields = {
          { name = "Title", id = "FIELD_TITLE" },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result_err = nil
      api_project.fetch_status_field(1, "khwerhahn", function(_, err)
        done = true
        result_err = err
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.truthy(result_err)
      assert.truthy(result_err:match("No 'Status' field"))
    end)
  end)

  describe("fetch_items_page", function()
    it("parses GraphQL response with items", function()
      local json = vim.json.encode({
        data = {
          node = {
            items = {
              pageInfo = { hasNextPage = false, endCursor = nil },
              nodes = {
                {
                  id = "PVTI_item_1",
                  fieldValueByName = { name = "Todo", optionId = "opt_todo" },
                  content = {
                    number = 42,
                    title = "Test issue",
                    body = "Description",
                    state = "OPEN",
                    assignees = { nodes = { { login = "alice" } } },
                    labels = { nodes = { { name = "bug", color = "d73a4a" } } },
                  },
                },
              },
            },
          },
        },
      })
      helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      local result_items = nil
      local result_page = nil
      api_project.fetch_items_page("PVT_123", nil, function(items, page_info)
        done = true
        result_items = items
        result_page = page_info
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.equals(1, #result_items)
      assert.equals("PVTI_item_1", result_items[1].id)
      assert.equals(42, result_items[1].content.number)
      assert.is_false(result_page.hasNextPage)
    end)

    it("passes cursor for pagination", function()
      local json = vim.json.encode({
        data = {
          node = {
            items = {
              pageInfo = { hasNextPage = false, endCursor = nil },
              nodes = {},
            },
          },
        },
      })
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = json },
      })

      local done = false
      api_project.fetch_items_page("PVT_123", "abc123cursor", function()
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.truthy(vim.tbl_contains(calls[1].cmd, "cursor=abc123cursor"))
    end)

    it("returns error on GraphQL failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "auth error" },
      })

      local done = false
      local result_err = nil
      api_project.fetch_items_page("PVT_123", nil, function(_, _, err)
        done = true
        result_err = err
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.truthy(result_err)
      assert.truthy(result_err:match("GraphQL query failed"))
    end)
  end)

  describe("build_board_data", function()
    local status_field = {
      id = "PVTSSF_status_123",
      options = {
        { id = "opt_todo", name = "Todo" },
        { id = "opt_doing", name = "In Progress" },
        { id = "opt_done", name = "Done" },
      },
    }

    local function make_item(issue_number, title, option_id)
      local item = {
        id = "PVTI_" .. issue_number,
        content = {
          number = issue_number,
          title = title,
          body = "",
          state = "OPEN",
          assignees = { nodes = {} },
          labels = { nodes = {} },
        },
      }
      if option_id then
        item.fieldValueByName = { name = "status", optionId = option_id }
      end
      return item
    end

    it("sorts items into columns by status option ID", function()
      local items = {
        make_item(1, "Todo task", "opt_todo"),
        make_item(2, "In prog", "opt_doing"),
        make_item(3, "Done task", "opt_done"),
        make_item(4, "Another todo", "opt_todo"),
      }

      local board = api_project.build_board_data(items, status_field, false, 100)

      assert.equals(3, #board.columns)
      assert.equals("Todo", board.columns[1].name)
      assert.equals(2, #board.columns[1].issues)
      assert.equals(1, board.columns[1].issues[1].number)
      assert.equals(4, board.columns[1].issues[2].number)
      assert.equals("In Progress", board.columns[2].name)
      assert.equals(1, #board.columns[2].issues)
      assert.equals("Done", board.columns[3].name)
      assert.equals(1, #board.columns[3].issues)
    end)

    it("puts items without status into unsorted", function()
      local items = {
        make_item(1, "Has status", "opt_todo"),
        make_item(2, "No status", nil),
      }

      local board = api_project.build_board_data(items, status_field, true, 100)

      assert.equals(1, #board.columns[1].issues)
      assert.is_not_nil(board.unsorted)
      assert.equals(1, #board.unsorted)
      assert.equals(2, board.unsorted[1].number)
    end)

    it("excludes unsorted when show_unsorted is false", function()
      local items = {
        make_item(1, "No status", nil),
      }

      local board = api_project.build_board_data(items, status_field, false, 100)
      assert.is_nil(board.unsorted)
    end)

    it("caps column items at done_limit", function()
      local items = {}
      for i = 1, 25 do
        table.insert(items, make_item(i, "Task " .. i, "opt_todo"))
      end

      local board = api_project.build_board_data(items, status_field, false, 10)

      assert.equals(10, #board.columns[1].issues)
      assert.equals(10, board.columns[1].limit)
    end)

    it("uses option ID as column label", function()
      local items = {}
      local board = api_project.build_board_data(items, status_field, false, 20)

      assert.equals("opt_todo", board.columns[1].label)
      assert.equals("opt_doing", board.columns[2].label)
      assert.equals("opt_done", board.columns[3].label)
    end)

    it("populates item_map cache", function()
      local items = {
        make_item(42, "Test", "opt_todo"),
        make_item(99, "Another", "opt_done"),
      }

      api_project.build_board_data(items, status_field, false, 100)

      assert.equals("PVTI_42", api_project.get_item_id(42))
      assert.equals("PVTI_99", api_project.get_item_id(99))
      assert.is_nil(api_project.get_item_id(1))
    end)

    it("skips draft issues (no number)", function()
      local items = {
        {
          id = "PVTI_draft",
          content = { title = "Draft note", body = "..." },
          fieldValueByName = { name = "Todo", optionId = "opt_todo" },
        },
        make_item(1, "Real issue", "opt_todo"),
      }

      local board = api_project.build_board_data(items, status_field, false, 100)
      assert.equals(1, #board.columns[1].issues)
      assert.equals(1, board.columns[1].issues[1].number)
    end)
  end)

  describe("fetch_all_columns", function()
    it("orchestrates ID resolution, field detection, field fetch, and item fetch", function()
      config.setup({
        source = "project",
        project = { number = 1, owner = "testowner" },
      })
      package.loaded["okuban.api_project"] = nil
      package.loaded["okuban.api"] = nil
      require("okuban.api")
      api_project = require("okuban.api_project")

      -- Response 1: resolve_project_id
      local project_json = vim.json.encode({ id = "PVT_123", title = "Test" })
      -- Response 2: detect_column_field (views GraphQL)
      local views_json = vim.json.encode({
        data = {
          node = {
            views = {
              nodes = {
                {
                  layout = "BOARD_LAYOUT",
                  verticalGroupByFields = {
                    nodes = { { name = "Status" } },
                  },
                },
              },
            },
          },
        },
      })
      -- Response 3: fetch_column_field
      local field_json = vim.json.encode({
        fields = {
          {
            name = "Status",
            id = "PVTSSF_1",
            options = {
              { id = "opt_a", name = "Todo" },
              { id = "opt_b", name = "Done" },
            },
          },
        },
      })
      -- Response 4: fetch_all_items (GraphQL)
      local items_json = vim.json.encode({
        data = {
          node = {
            items = {
              pageInfo = { hasNextPage = false },
              nodes = {
                {
                  id = "PVTI_1",
                  fieldValueByName = { name = "Todo", optionId = "opt_a" },
                  content = {
                    number = 10,
                    title = "Test issue",
                    body = "",
                    state = "OPEN",
                    assignees = { nodes = {} },
                    labels = { nodes = {} },
                  },
                },
              },
            },
          },
        },
      })

      helpers.mock_vim_system({
        { code = 0, stdout = project_json },
        { code = 0, stdout = views_json },
        { code = 0, stdout = field_json },
        { code = 0, stdout = items_json },
      })

      local done = false
      local result = nil
      api_project.fetch_all_columns(function(data)
        done = true
        result = data
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(2, #result.columns)
      assert.equals("Todo", result.columns[1].name)
      assert.equals(1, #result.columns[1].issues)
      assert.equals(10, result.columns[1].issues[1].number)
      assert.equals("Done", result.columns[2].name)
      assert.equals(0, #result.columns[2].issues)
    end)

    it("detects non-Status column field from Board view", function()
      config.setup({
        source = "project",
        project = { number = 1, owner = "testowner" },
      })
      package.loaded["okuban.api_project"] = nil
      package.loaded["okuban.api"] = nil
      require("okuban.api")
      api_project = require("okuban.api_project")

      -- Response 1: resolve_project_id
      local project_json = vim.json.encode({ id = "PVT_123", title = "Test" })
      -- Response 2: detect_column_field — Board uses "Workflow Stage"
      local views_json = vim.json.encode({
        data = {
          node = {
            views = {
              nodes = {
                {
                  layout = "BOARD_LAYOUT",
                  verticalGroupByFields = {
                    nodes = { { name = "Workflow Stage" } },
                  },
                },
              },
            },
          },
        },
      })
      -- Response 3: fetch_column_field — searches for "Workflow Stage"
      local field_json = vim.json.encode({
        fields = {
          {
            name = "Status",
            id = "PVTSSF_status",
            options = { { id = "opt_s", name = "Todo" } },
          },
          {
            name = "Workflow Stage",
            id = "PVTSSF_workflow",
            options = {
              { id = "opt_inv", name = "Investigation Needed" },
              { id = "opt_wip", name = "In Progress" },
              { id = "opt_done", name = "Done" },
            },
          },
        },
      })
      -- Response 4: fetch_all_items (GraphQL)
      local items_json = vim.json.encode({
        data = {
          node = {
            items = {
              pageInfo = { hasNextPage = false },
              nodes = {
                {
                  id = "PVTI_1",
                  fieldValueByName = { name = "Investigation Needed", optionId = "opt_inv" },
                  content = {
                    number = 42,
                    title = "Investigate bug",
                    body = "",
                    state = "OPEN",
                    assignees = { nodes = {} },
                    labels = { nodes = {} },
                  },
                },
              },
            },
          },
        },
      })

      helpers.mock_vim_system({
        { code = 0, stdout = project_json },
        { code = 0, stdout = views_json },
        { code = 0, stdout = field_json },
        { code = 0, stdout = items_json },
      })

      local done = false
      local result = nil
      api_project.fetch_all_columns(function(data)
        done = true
        result = data
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(3, #result.columns)
      assert.equals("Investigation Needed", result.columns[1].name)
      assert.equals(1, #result.columns[1].issues)
      assert.equals(42, result.columns[1].issues[1].number)
      assert.equals("In Progress", result.columns[2].name)
      assert.equals("Done", result.columns[3].name)
      assert.equals("Workflow Stage", api_project.get_cached_column_field_name())
    end)

    it("uses cached project_id, column_field_name, and status_field on subsequent calls", function()
      config.setup({
        source = "project",
        project = { number = 1, owner = "testowner" },
      })
      package.loaded["okuban.api_project"] = nil
      package.loaded["okuban.api"] = nil
      require("okuban.api")
      api_project = require("okuban.api_project")

      -- Pre-set all caches
      api_project._set_cache("PVT_cached", {
        id = "PVTSSF_cached",
        options = {
          { id = "opt_x", name = "Backlog" },
        },
      }, "Status")

      -- Only one call needed: GraphQL items fetch
      local items_json = vim.json.encode({
        data = {
          node = {
            items = {
              pageInfo = { hasNextPage = false },
              nodes = {},
            },
          },
        },
      })
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = items_json },
      })

      local done = false
      local result = nil
      api_project.fetch_all_columns(function(data)
        done = true
        result = data
      end)

      vim.wait(2000, function()
        return done
      end)

      -- Only 1 call (items fetch), not 4
      assert.equals(1, #calls)
      assert.is_not_nil(result)
      assert.equals(1, #result.columns)
      assert.equals("Backlog", result.columns[1].name)
    end)

    it("returns nil when project not configured", function()
      config.setup({ source = "project", project = {} })
      package.loaded["okuban.api_project"] = nil
      package.loaded["okuban.api"] = nil
      require("okuban.api")
      api_project = require("okuban.api_project")

      local done = false
      local result = "not_nil"
      api_project.fetch_all_columns(function(data)
        done = true
        result = data
      end)

      -- Synchronous path (no async call needed)
      vim.wait(1000, function()
        return done
      end)
      assert.is_nil(result)
    end)
  end)

  describe("move_item", function()
    it("calls gh project item-edit with correct arguments", function()
      local calls = helpers.mock_vim_system({
        { code = 0 },
      })

      local done = false
      local success = false
      api_project.move_item("PVTI_1", "PVT_123", "PVTSSF_status", "opt_done", function(ok)
        done = true
        success = ok
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(success)
      local cmd = calls[1].cmd
      assert.truthy(vim.tbl_contains(cmd, "project"))
      assert.truthy(vim.tbl_contains(cmd, "item-edit"))
      assert.truthy(vim.tbl_contains(cmd, "--id"))
      assert.truthy(vim.tbl_contains(cmd, "PVTI_1"))
      assert.truthy(vim.tbl_contains(cmd, "--project-id"))
      assert.truthy(vim.tbl_contains(cmd, "PVT_123"))
      assert.truthy(vim.tbl_contains(cmd, "--field-id"))
      assert.truthy(vim.tbl_contains(cmd, "PVTSSF_status"))
      assert.truthy(vim.tbl_contains(cmd, "--single-select-option-id"))
      assert.truthy(vim.tbl_contains(cmd, "opt_done"))
    end)

    it("returns error on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "permission denied" },
      })

      local done = false
      local result_err = nil
      api_project.move_item("PVTI_1", "PVT_123", "PVTSSF_status", "opt_done", function(_, err)
        done = true
        result_err = err
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.truthy(result_err)
    end)
  end)

  describe("cache accessors", function()
    it("get_item_id returns nil for unknown issues", function()
      assert.is_nil(api_project.get_item_id(999))
    end)

    it("get_cached_status_field returns nil before fetch", function()
      assert.is_nil(api_project.get_cached_status_field())
    end)

    it("get_cached_project_id returns nil before fetch", function()
      assert.is_nil(api_project.get_cached_project_id())
    end)

    it("reset_cache clears all cached data", function()
      api_project._set_cache("PVT_test", { id = "FIELD_test", options = {} }, "Workflow Stage")
      assert.equals("PVT_test", api_project.get_cached_project_id())
      assert.equals("Workflow Stage", api_project.get_cached_column_field_name())
      api_project.reset_cache()
      assert.is_nil(api_project.get_cached_project_id())
      assert.is_nil(api_project.get_cached_status_field())
      assert.is_nil(api_project.get_cached_column_field_name())
    end)
  end)
end)

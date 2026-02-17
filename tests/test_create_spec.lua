local helpers = require("tests.helpers")

describe("okuban.create", function()
  local create

  before_each(function()
    create = require("okuban.ui.create")
    create._reset_cache()
  end)

  -- -----------------------------------------------------------------------
  -- _parse_frontmatter
  -- -----------------------------------------------------------------------
  describe("_parse_frontmatter", function()
    it("returns original content when no frontmatter", function()
      local body, labels, name = create._parse_frontmatter("Hello world\n\nSome content")
      assert.equals("Hello world\n\nSome content", body)
      assert.same({}, labels)
      assert.is_nil(name)
    end)

    it("returns empty for nil input", function()
      local body, labels, name = create._parse_frontmatter(nil)
      assert.equals("", body)
      assert.same({}, labels)
      assert.is_nil(name)
    end)

    it("returns empty for empty input", function()
      local body, labels, name = create._parse_frontmatter("")
      assert.equals("", body)
      assert.same({}, labels)
      assert.is_nil(name)
    end)

    it("strips frontmatter and extracts inline labels", function()
      local content =
        '---\nname: "Bug report"\nlabels: ["type: bug", "needs: triage"]\n---\n\n## Bug\n\nDescribe the bug'
      local body, labels, name = create._parse_frontmatter(content)
      assert.equals("## Bug\n\nDescribe the bug", body)
      assert.same({ "type: bug", "needs: triage" }, labels)
      assert.equals("Bug report", name)
    end)

    it("strips frontmatter and extracts multiline labels", function()
      local content =
        "---\nname: Feature request\nlabels:\n  - type: feature\n  - priority: medium\n---\n\n## Feature\n\nDescribe"
      local body, labels, name = create._parse_frontmatter(content)
      assert.equals("## Feature\n\nDescribe", body)
      assert.same({ "type: feature", "priority: medium" }, labels)
      assert.equals("Feature request", name)
    end)

    it("handles frontmatter with no labels field", function()
      local content = '---\nname: "Simple"\n---\n\nBody here'
      local body, labels, name = create._parse_frontmatter(content)
      assert.equals("Body here", body)
      assert.same({}, labels)
      assert.equals("Simple", name)
    end)

    it("handles frontmatter with no name field", function()
      local content = '---\nlabels: ["bug"]\n---\n\nBody'
      local body, labels, name = create._parse_frontmatter(content)
      assert.equals("Body", body)
      assert.same({ "bug" }, labels)
      assert.is_nil(name)
    end)

    it("handles unclosed frontmatter", function()
      local content = "---\nname: test\nlabels: [bug]\nno closing delimiter"
      local body, labels, name = create._parse_frontmatter(content)
      -- Should return original content since frontmatter is not properly closed
      assert.equals(content, body)
      assert.same({}, labels)
      assert.is_nil(name)
    end)

    it("strips leading newlines from body after frontmatter", function()
      local content = "---\nname: test\n---\n\n\n\nBody starts here"
      local body, labels, name = create._parse_frontmatter(content)
      assert.equals("Body starts here", body)
      assert.same({}, labels)
      assert.equals("test", name)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- create_issue API
  -- -----------------------------------------------------------------------
  describe("create_issue API", function()
    local api

    before_each(function()
      api = require("okuban.api")
    end)

    after_each(function()
      helpers.restore_vim_system()
    end)

    it("calls gh issue create with correct args", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "https://github.com/owner/repo/issues/42\n" },
      })

      local result_ok, result_number
      api.create_issue("Test title", "Test body", { "bug" }, function(ok, number)
        result_ok = ok
        result_number = number
      end)

      vim.wait(1000, function()
        return result_ok ~= nil
      end)

      assert.is_true(result_ok)
      assert.equals(42, result_number)
      -- Verify command structure
      assert.truthy(calls[1])
      local cmd_str = table.concat(calls[1].cmd, " ")
      assert.truthy(cmd_str:find("issue create"))
      assert.truthy(cmd_str:find("Test title"))
      assert.truthy(cmd_str:find("Test body"))
      assert.truthy(cmd_str:find("bug"))
    end)

    it("includes multiple labels in command", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "https://github.com/owner/repo/issues/99\n" },
      })

      local done = false
      api.create_issue("Title", "Body", { "okuban:todo", "type: feature" }, function()
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      local cmd_str = table.concat(calls[1].cmd, " ")
      assert.truthy(cmd_str:find("okuban:todo"))
      assert.truthy(cmd_str:find("type: feature"))
    end)

    it("returns error on failure", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "permission denied" },
      })

      local result_ok, result_err
      api.create_issue("Title", "Body", {}, function(ok, _, err)
        result_ok = ok
        result_err = err
      end)

      vim.wait(1000, function()
        return result_ok ~= nil
      end)

      assert.is_false(result_ok)
      assert.truthy(result_err:find("permission denied"))
    end)

    it("handles missing issue number in output", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "Created issue successfully\n" },
      })

      local result_ok, result_number
      api.create_issue("Title", "Body", {}, function(ok, number)
        result_ok = ok
        result_number = number
      end)

      vim.wait(1000, function()
        return result_ok ~= nil
      end)

      assert.is_true(result_ok)
      assert.is_nil(result_number)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Config
  -- -----------------------------------------------------------------------
  describe("config", function()
    it("has new_issue keymap default", function()
      local cfg = require("okuban.config")
      cfg.setup()
      assert.equals("n", cfg.get().keymaps.new_issue)
    end)

    it("allows new_issue keymap override", function()
      local cfg = require("okuban.config")
      cfg.setup({ keymaps = { new_issue = "N" } })
      assert.equals("N", cfg.get().keymaps.new_issue)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Template cache
  -- -----------------------------------------------------------------------
  describe("template cache", function()
    it("_reset_cache clears template cache", function()
      -- Just verify it doesn't error
      create._reset_cache()
      -- After reset, next _fetch_templates should make API call (not use cache)
      -- This is a smoke test for the reset function
      assert.truthy(create._reset_cache)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- close
  -- -----------------------------------------------------------------------
  describe("close", function()
    it("handles close when no window is open", function()
      -- Should not error
      create.close()
      assert.truthy(true)
    end)
  end)
end)

describe("okuban.ui.card", function()
  local card_mod

  before_each(function()
    package.loaded["okuban.ui.card"] = nil
    package.loaded["okuban.config"] = nil
    require("okuban.config")
    card_mod = require("okuban.ui.card")
  end)

  describe("wrap_text", function()
    it("wraps text at word boundaries", function()
      local lines = card_mod.wrap_text("hello world foo bar", 11)
      assert.equals(2, #lines)
      assert.equals("hello world", lines[1])
      assert.equals("foo bar", lines[2])
    end)

    it("returns single line when text fits", function()
      local lines = card_mod.wrap_text("hello", 20)
      assert.equals(1, #lines)
      assert.equals("hello", lines[1])
    end)

    it("handles word longer than width", function()
      local lines = card_mod.wrap_text("superlongword short", 5)
      assert.equals(2, #lines)
      assert.equals("superlongword", lines[1])
      assert.equals("short", lines[2])
    end)

    it("returns empty string for empty input", function()
      local lines = card_mod.wrap_text("", 10)
      assert.equals(1, #lines)
      assert.equals("", lines[1])
    end)

    it("returns empty string for nil input", function()
      local lines = card_mod.wrap_text(nil, 10)
      assert.equals(1, #lines)
      assert.equals("", lines[1])
    end)

    it("handles exact fit", function()
      local lines = card_mod.wrap_text("abc def", 7)
      assert.equals(1, #lines)
      assert.equals("abc def", lines[1])
    end)

    it("wraps multi-word text into multiple lines", function()
      local lines = card_mod.wrap_text("a b c d e f", 3)
      assert.equals(3, #lines)
      assert.equals("a b", lines[1])
      assert.equals("c d", lines[2])
      assert.equals("e f", lines[3])
    end)
  end)

  describe("strip_commit_prefix", function()
    it("strips type(scope): prefix and capitalizes", function()
      local title, tag = card_mod.strip_commit_prefix("feat(api): preflight checks")
      assert.equals("Preflight checks", title)
      assert.equals("feat", tag)
    end)

    it("strips type: prefix without scope", function()
      local title, tag = card_mod.strip_commit_prefix("fix: broken link in readme")
      assert.equals("Broken link in readme", title)
      assert.equals("fix", tag)
    end)

    it("passes through plain titles", function()
      local title, tag = card_mod.strip_commit_prefix("Add board rendering")
      assert.equals("Add board rendering", title)
      assert.is_nil(tag)
    end)

    it("handles empty title", function()
      local title, tag = card_mod.strip_commit_prefix("")
      assert.equals("", title)
      assert.is_nil(tag)
    end)

    it("handles nil title", function()
      local title, tag = card_mod.strip_commit_prefix(nil)
      assert.equals("", title)
      assert.is_nil(tag)
    end)

    it("handles nested parentheses in scope", function()
      local title, tag = card_mod.strip_commit_prefix("test(e2e): integration tests")
      assert.equals("Integration tests", title)
      assert.equals("test", tag)
    end)

    it("capitalizes first letter of description", function()
      local title, _ = card_mod.strip_commit_prefix("docs: update readme")
      assert.equals("Update readme", title)
    end)
  end)

  describe("extract_tldr", function()
    it("extracts text from ## Summary section", function()
      local body = "## Summary\nCreate the plugin skeleton.\n\n## Deliverables\n- stuff"
      local tldr = card_mod.extract_tldr(body)
      assert.equals("Create the plugin skeleton.", tldr)
    end)

    it("extracts text from ## Bug section", function()
      local body = "## Bug\nDone column shows 0 issues.\n\n## Fix\n- stuff"
      local tldr = card_mod.extract_tldr(body)
      assert.equals("Done column shows 0 issues.", tldr)
    end)

    it("joins multi-line summary into one string", function()
      local body = "## Summary\nFirst line\nsecond line.\n\n## Deliverables"
      local tldr = card_mod.extract_tldr(body)
      assert.equals("First line second line.", tldr)
    end)

    it("strips markdown backticks", function()
      local body = "## Bug\nThe `fetch_column()` function fails.\n\n## Fix"
      local tldr = card_mod.extract_tldr(body)
      assert.equals("The fetch_column() function fails.", tldr)
    end)

    it("strips bold markers", function()
      local body = "## Summary\nThis is **important** text.\n\n## Details"
      local tldr = card_mod.extract_tldr(body)
      assert.equals("This is important text.", tldr)
    end)

    it("falls back to first non-heading line", function()
      local body = "# Title\nFirst paragraph text.\n\nMore stuff."
      local tldr = card_mod.extract_tldr(body)
      assert.equals("First paragraph text.", tldr)
    end)

    it("returns nil for empty body", function()
      assert.is_nil(card_mod.extract_tldr(""))
    end)

    it("returns nil for nil body", function()
      assert.is_nil(card_mod.extract_tldr(nil))
    end)

    it("returns nil for body with only headings", function()
      assert.is_nil(card_mod.extract_tldr("## Heading\n## Another"))
    end)
  end)

  describe("format_compact_metadata", function()
    it("shows type tag and assignee", function()
      local issue = { assignees = { { login = "alice" } }, labels = {} }
      local meta = card_mod.format_compact_metadata(issue, "feat")
      assert.truthy(meta:match("feat"))
      assert.truthy(meta:match("@alice"))
    end)

    it("falls back to type: label when no tag", function()
      local issue = {
        assignees = {},
        labels = { { name = "type: bug" }, { name = "okuban:todo" } },
      }
      local meta = card_mod.format_compact_metadata(issue, nil)
      assert.equals("bug", meta)
    end)

    it("shows only assignee when no type", function()
      local issue = { assignees = { { login = "bob" } }, labels = {} }
      local meta = card_mod.format_compact_metadata(issue, nil)
      assert.equals("@bob", meta)
    end)

    it("returns nil when no metadata available", function()
      local issue = { assignees = {}, labels = {} }
      assert.is_nil(card_mod.format_compact_metadata(issue, nil))
    end)

    it("skips okuban labels when looking for type", function()
      local issue = {
        assignees = {},
        labels = { { name = "okuban:done" } },
      }
      assert.is_nil(card_mod.format_compact_metadata(issue, nil))
    end)
  end)

  describe("render_card", function()
    it("returns a single string", function()
      local result = card_mod.render_card({ number = 1, title = "Test" }, 30)
      assert.is_string(result)
    end)

    it("includes issue number", function()
      local result = card_mod.render_card({ number = 42, title = "Test" }, 30)
      assert.truthy(result:match("#42"))
    end)

    it("strips commit prefix", function()
      local result = card_mod.render_card({ number = 2, title = "feat(api): preflight checks" }, 40)
      assert.truthy(result:match("Preflight checks"))
      assert.is_falsy(result:match("feat%(api%)"))
    end)

    it("truncates long titles with ellipsis", function()
      local result = card_mod.render_card({ number = 1, title = "A very long title that will be truncated" }, 20)
      assert.truthy(result:match("\xe2\x80\xa6"))
    end)

    it("does not truncate short titles", function()
      local result = card_mod.render_card({ number = 1, title = "Short" }, 30)
      assert.is_falsy(result:match("\xe2\x80\xa6"))
      assert.truthy(result:match("Short"))
    end)

    it("handles missing title", function()
      local result = card_mod.render_card({ number = 1 }, 20)
      assert.truthy(result:match("#1"))
    end)

    it("handles large issue numbers", function()
      local result = card_mod.render_card({ number = 12345, title = "Big" }, 40)
      assert.truthy(result:match("#12345"))
      assert.truthy(result:match("Big"))
    end)

    it("shows worktree badge when worktree exists", function()
      local wt_map = { [42] = { path = "/wt", branch = "feat/issue-42", dirty = false } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, wt_map)
      -- Should contain circle indicator
      assert.truthy(result:match("\xe2\x97\x8b")) -- U+25CB WHITE CIRCLE (clean)
    end)

    it("shows dirty badge for dirty worktree", function()
      local wt_map = { [42] = { path = "/wt", branch = "feat/issue-42", dirty = true } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, wt_map)
      assert.truthy(result:match("\xe2\x97\x8f")) -- U+25CF BLACK CIRCLE (dirty)
    end)

    it("no badge for active worktree (uses highlight instead)", function()
      local wt_map = { [42] = { path = "/wt", branch = "feat/issue-42", active = true } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, wt_map)
      -- Active worktrees use OkubanCardActive highlight, no badge
      assert.is_falsy(result:match("\xe2\xac\xa4")) -- No U+2B24
      assert.is_falsy(result:match("\xe2\x97\x8b")) -- No U+25CB
      assert.is_falsy(result:match("\xe2\x97\x8f")) -- No U+25CF
      assert.truthy(result:match("Test")) -- Title still present
    end)

    it("no badge when issue not in worktree map", function()
      local wt_map = { [99] = { path = "/wt", branch = "feat/issue-99" } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, wt_map)
      assert.is_falsy(result:match("\xe2\x97\x8b"))
      assert.is_falsy(result:match("\xe2\x97\x8f"))
      assert.is_falsy(result:match("\xe2\xac\xa4"))
    end)

    it("no badge when worktree_map is nil", function()
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil)
      assert.is_falsy(result:match("\xe2\x97\x8b"))
      assert.is_falsy(result:match("\xe2\x97\x8f"))
    end)

    it("shows running badge for running Claude session", function()
      local sessions = { [42] = { status = "running" } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, sessions)
      assert.truthy(result:match("\xe2\x96\xb6")) -- U+25B6 RIGHT-POINTING TRIANGLE
    end)

    it("shows completed badge for completed Claude session", function()
      local sessions = { [42] = { status = "completed" } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, sessions)
      assert.truthy(result:match("\xe2\x9c\x93")) -- U+2713 CHECK MARK
    end)

    it("shows failed badge for failed Claude session", function()
      local sessions = { [42] = { status = "failed" } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, sessions)
      assert.truthy(result:match("\xe2\x9c\x97")) -- U+2717 BALLOT X
    end)

    it("shows initializing badge for initializing Claude session", function()
      local sessions = { [42] = { status = "initializing" } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, sessions)
      assert.truthy(result:match("\xe2\x80\xa6")) -- U+2026 HORIZONTAL ELLIPSIS
    end)

    it("no session badge when no session exists", function()
      local sessions = { [99] = { status = "running" } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, sessions)
      assert.is_falsy(result:match("\xe2\x96\xb6"))
      assert.is_falsy(result:match("\xe2\x9c\x93"))
      assert.is_falsy(result:match("\xe2\x9c\x97"))
    end)

    it("shows sub-issue count badge from counts map", function()
      local counts = { [42] = { total = 3, completed = 1 } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, nil, counts)
      assert.truthy(result:match("%(3%)"))
    end)

    it("shows sub-issue count badge from issue.sub_issue_counts (project mode)", function()
      local issue = { number = 42, title = "Test", sub_issue_counts = { total = 5, completed = 2 } }
      local result = card_mod.render_card(issue, 40)
      assert.truthy(result:match("%(5%)"))
    end)

    it("no sub-issue badge when count is 0", function()
      local counts = { [42] = { total = 0, completed = 0 } }
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, nil, counts)
      assert.is_falsy(result:match("%(0%)"))
    end)

    it("no sub-issue badge when counts is nil", function()
      local result = card_mod.render_card({ number = 42, title = "Test" }, 40, nil, nil, nil)
      assert.is_falsy(result:match("%(%d+%)"))
    end)

    it("truncates title correctly with sub-issue badge", function()
      local counts = { [1] = { total = 3, completed = 1 } }
      local result =
        card_mod.render_card({ number = 1, title = "A very long title that will be truncated" }, 25, nil, nil, counts)
      assert.truthy(result:match("%(3%)"))
      assert.truthy(result:match("\xe2\x80\xa6")) -- ellipsis
    end)
  end)

  describe("render_column", function()
    it("renders one line per card", function()
      local issues = {
        { number = 1, title = "First" },
        { number = 2, title = "Second" },
        { number = 3, title = "Third" },
      }
      local lines, card_ranges = card_mod.render_column(issues, 30)
      assert.equals(3, #lines)
      assert.equals(3, #card_ranges)
    end)

    it("shows placeholder for empty column", function()
      local lines, card_ranges = card_mod.render_column({}, 30)
      assert.equals(1, #lines)
      assert.equals("  (no issues)", lines[1])
      assert.equals(0, #card_ranges)
    end)

    it("card_ranges are one-to-one with lines", function()
      local issues = {
        { number = 1, title = "First" },
        { number = 2, title = "Second" },
      }
      local _, card_ranges = card_mod.render_column(issues, 30)
      for i, range in ipairs(card_ranges) do
        assert.equals(i, range.start_line)
        assert.equals(i, range.end_line)
      end
    end)

    it("each line contains its issue number", function()
      local issues = {
        { number = 10, title = "Alpha" },
        { number = 20, title = "Beta" },
      }
      local lines, _ = card_mod.render_column(issues, 30)
      assert.truthy(lines[1]:match("#10"))
      assert.truthy(lines[2]:match("#20"))
    end)

    it("passes sub_issue_counts through to cards", function()
      local issues = {
        { number = 10, title = "Alpha" },
        { number = 20, title = "Beta" },
      }
      local counts = { [10] = { total = 3, completed = 1 } }
      local lines, _ = card_mod.render_column(issues, 40, nil, nil, counts)
      assert.truthy(lines[1]:match("%(3%)"))
      assert.is_falsy(lines[2]:match("%(%d+%)"))
    end)
  end)

  describe("render_preview", function()
    it("returns height lines", function()
      local issue = { number = 1, title = "Test", assignees = {}, labels = {} }
      local lines = card_mod.render_preview(issue, 80, 5)
      assert.equals(5, #lines)
    end)

    it("shows full title with issue number", function()
      local issue = { number = 42, title = "feat(api): add authentication flow for OAuth" }
      local lines = card_mod.render_preview(issue, 80, 5)
      assert.truthy(lines[1]:match("#42"))
      assert.truthy(lines[1]:match("Add authentication flow for OAuth"))
    end)

    it("word-wraps long titles", function()
      local issue = { number = 1, title = "A very long title that needs word wrapping to fit properly" }
      local lines = card_mod.render_preview(issue, 30, 5)
      -- Title should span multiple lines
      local non_empty = 0
      for _, line in ipairs(lines) do
        if line ~= "" then
          non_empty = non_empty + 1
        end
      end
      assert.is_true(non_empty >= 2)
    end)

    it("shows TLDR from body", function()
      local issue = {
        number = 1,
        title = "Fix bug",
        body = "## Summary\nThe fetch function fails silently.\n\n## Fix",
        assignees = {},
        labels = {},
      }
      local lines = card_mod.render_preview(issue, 80, 5)
      local found = false
      for _, line in ipairs(lines) do
        if line:match("fetch function fails") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("shows metadata", function()
      local issue = {
        number = 1,
        title = "feat(ui): add board",
        assignees = { { login = "alice" } },
        labels = {},
      }
      local lines = card_mod.render_preview(issue, 80, 5)
      local found = false
      for _, line in ipairs(lines) do
        if line:match("@alice") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("returns empty lines for nil issue", function()
      local lines = card_mod.render_preview(nil, 80, 5)
      assert.equals(5, #lines)
      for _, line in ipairs(lines) do
        assert.equals("", line)
      end
    end)

    it("pads short content to height", function()
      local issue = { number = 1, title = "Short", assignees = {}, labels = {} }
      local lines = card_mod.render_preview(issue, 80, 10)
      assert.equals(10, #lines)
    end)

    it("shows sub-issue progress from counts map", function()
      local issue = { number = 42, title = "Test", assignees = {}, labels = {} }
      local counts = { [42] = { total = 5, completed = 2 } }
      local lines = card_mod.render_preview(issue, 80, 10, nil, nil, counts)
      local found = false
      for _, line in ipairs(lines) do
        if line:match("2/5 sub%-issues") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("shows sub-issue progress from issue.sub_issue_counts (project mode)", function()
      local issue = {
        number = 42,
        title = "Test",
        assignees = {},
        labels = {},
        sub_issue_counts = { total = 3, completed = 3 },
      }
      local lines = card_mod.render_preview(issue, 80, 10)
      local found = false
      for _, line in ipairs(lines) do
        if line:match("3/3 sub%-issues") then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("no sub-issue line when counts are 0 or nil", function()
      local issue = { number = 42, title = "Test", assignees = {}, labels = {} }
      local lines = card_mod.render_preview(issue, 80, 10, nil, nil, nil)
      for _, line in ipairs(lines) do
        assert.is_falsy(line:match("sub%-issues"))
      end
    end)

    it("shows initializing status in preview for initializing session", function()
      local issue = { number = 42, title = "Test", assignees = {}, labels = {} }
      local sessions = { [42] = { status = "initializing" } }
      local lines = card_mod.render_preview(issue, 80, 10, nil, sessions)
      local found = false
      for _, line in ipairs(lines) do
        if line:match("initializing") then
          found = true
        end
      end
      assert.is_true(found, "expected 'initializing' in preview")
    end)

    it("shows running status in preview for running session", function()
      local issue = { number = 42, title = "Test", assignees = {}, labels = {} }
      local sessions = { [42] = { status = "running" } }
      local lines = card_mod.render_preview(issue, 80, 10, nil, sessions)
      local found = false
      for _, line in ipairs(lines) do
        if line:match("running") then
          found = true
        end
      end
      assert.is_true(found, "expected 'running' in preview")
    end)

    it("respects show_tldr config", function()
      local config_mod = require("okuban.config")
      config_mod.setup({ show_tldr = false })
      package.loaded["okuban.ui.card"] = nil
      card_mod = require("okuban.ui.card")

      local issue = {
        number = 1,
        title = "Fix bug",
        body = "## Summary\nThis should not appear.\n\n## End",
        assignees = {},
        labels = {},
      }
      local lines = card_mod.render_preview(issue, 80, 5)
      for _, line in ipairs(lines) do
        assert.is_falsy(line:match("should not appear"))
      end
    end)
  end)
end)

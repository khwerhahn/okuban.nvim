local helpers = require("tests.helpers")

describe("okuban.detect", function()
  local detect

  before_each(function()
    package.loaded["okuban.detect"] = nil
    package.loaded["okuban.config"] = nil
    detect = require("okuban.detect")
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("parse_branch_name", function()
    it("extracts from feat/issue-42-description", function()
      assert.equals(42, detect.parse_branch_name("feat/issue-42-description"))
    end)

    it("extracts from fix/issue-123-null-check", function()
      assert.equals(123, detect.parse_branch_name("fix/issue-123-null-check"))
    end)

    it("extracts from feat/issue-42 (no description)", function()
      assert.equals(42, detect.parse_branch_name("feat/issue-42"))
    end)

    it("extracts from GH-42-oauth", function()
      assert.equals(42, detect.parse_branch_name("GH-42-oauth"))
    end)

    it("extracts from gh-7-fix", function()
      assert.equals(7, detect.parse_branch_name("gh-7-fix"))
    end)

    it("extracts from feat/42-login", function()
      assert.equals(42, detect.parse_branch_name("feat/42-login"))
    end)

    it("extracts from fix/123-null", function()
      assert.equals(123, detect.parse_branch_name("fix/123-null"))
    end)

    it("extracts from 42-add-login", function()
      assert.equals(42, detect.parse_branch_name("42-add-login"))
    end)

    it("returns nil for main", function()
      assert.is_nil(detect.parse_branch_name("main"))
    end)

    it("returns nil for develop", function()
      assert.is_nil(detect.parse_branch_name("develop"))
    end)

    it("returns nil for branch without number", function()
      assert.is_nil(detect.parse_branch_name("feat/add-login"))
    end)

    it("prefers issue-N pattern over bare number", function()
      -- "feat/issue-42-fix-99" should return 42, not 99
      assert.equals(42, detect.parse_branch_name("feat/issue-42-fix-99"))
    end)
  end)

  describe("parse_commit_messages", function()
    it("finds #42 in a single commit", function()
      assert.equals(42, detect.parse_commit_messages("fix: handle null check (#42)"))
    end)

    it("finds most referenced issue across multiple commits", function()
      local text = table.concat({
        "feat(ui): add board (Refs #10)",
        "fix: null check (Refs #10)",
        "docs: update readme (Refs #20)",
      }, "\n")
      assert.equals(10, detect.parse_commit_messages(text))
    end)

    it("handles Fixes #N keyword", function()
      assert.equals(15, detect.parse_commit_messages("fix(api): handle error (Fixes #15)"))
    end)

    it("handles Closes #N keyword", function()
      assert.equals(7, detect.parse_commit_messages("feat: done (Closes #7)"))
    end)

    it("returns nil when no references found", function()
      assert.is_nil(detect.parse_commit_messages("chore: update deps"))
    end)

    it("returns nil for empty string", function()
      assert.is_nil(detect.parse_commit_messages(""))
    end)
  end)

  describe("detect_from_branch", function()
    it("parses branch from git output", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "feat/issue-42-auto-focus\n" },
      })

      local result = detect.detect_from_branch()
      assert.equals(42, result)
    end)

    it("returns nil on detached HEAD", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "HEAD\n" },
      })

      assert.is_nil(detect.detect_from_branch())
    end)

    it("returns nil on git error", function()
      helpers.mock_vim_system({
        { code = 128, stderr = "not a git repository" },
      })

      assert.is_nil(detect.detect_from_branch())
    end)
  end)

  describe("detect_from_commits", function()
    it("finds issue from recent commits", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "feat: add board (Refs #10)\nfix: null check (Refs #10)\n" },
      })

      local result = detect.detect_from_commits()
      assert.equals(10, result)
    end)

    it("returns nil when no commits have references", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "chore: update deps\nchore: clean up\n" },
      })

      assert.is_nil(detect.detect_from_commits())
    end)
  end)

  describe("detect_from_gh", function()
    it("returns issue number from gh CLI", function()
      helpers.mock_vim_system({
        { code = 0, stdout = '[{"number":42}]' },
      })

      local done = false
      local result = nil
      detect.detect_from_gh(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(42, result)
    end)

    it("returns nil when no in-progress issues", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "[]" },
      })

      local done = false
      local result = "not_called"
      detect.detect_from_gh(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result)
    end)

    it("returns nil on gh error", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "auth required" },
      })

      local done = false
      local result = "not_called"
      detect.detect_from_gh(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result)
    end)
  end)

  describe("detect_issue cascade", function()
    it("uses branch name when available (tier 1)", function()
      -- First call is git rev-parse for branch, returns valid branch
      helpers.mock_vim_system({
        { code = 0, stdout = "feat/issue-42-auto-focus\n" },
      })

      local done = false
      local result = nil
      detect.detect_issue(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(42, result)
    end)

    it("falls back to commits when branch has no number (tier 2)", function()
      helpers.mock_vim_system({
        -- git rev-parse: branch with no issue number
        { code = 0, stdout = "main\n" },
        -- git log: commits with issue refs
        { code = 0, stdout = "feat: add board (Refs #10)\n" },
      })

      local done = false
      local result = nil
      detect.detect_issue(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(10, result)
    end)

    it("falls back to gh CLI when branch and commits fail (tier 3)", function()
      helpers.mock_vim_system({
        -- git rev-parse: no issue number
        { code = 0, stdout = "main\n" },
        -- git log: no refs
        { code = 0, stdout = "chore: update deps\n" },
        -- gh issue list: returns in-progress issue
        { code = 0, stdout = '[{"number":7}]' },
      })

      local done = false
      local result = nil
      detect.detect_issue(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(7, result)
    end)

    it("returns nil when all tiers fail", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "main\n" },
        { code = 0, stdout = "chore: update deps\n" },
        { code = 0, stdout = "[]" },
      })

      local done = false
      local result = "not_called"
      detect.detect_issue(function(num)
        done = true
        result = num
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result)
    end)
  end)
end)

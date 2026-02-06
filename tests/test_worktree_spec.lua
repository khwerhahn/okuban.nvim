local helpers = require("tests.helpers")

describe("okuban.worktree", function()
  local wt

  before_each(function()
    package.loaded["okuban.worktree"] = nil
    package.loaded["okuban.detect"] = nil
    package.loaded["okuban.config"] = nil
    wt = require("okuban.worktree")
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("parse_porcelain", function()
    it("parses a single worktree entry", function()
      local output = table.concat({
        "worktree /home/user/project",
        "HEAD abc123",
        "branch refs/heads/main",
        "",
      }, "\n")

      local result = wt.parse_porcelain(output)
      assert.equals(1, #result)
      assert.equals("/home/user/project", result[1].path)
      assert.equals("abc123", result[1].head)
      assert.equals("main", result[1].branch)
    end)

    it("parses multiple worktree entries", function()
      local output = table.concat({
        "worktree /home/user/project",
        "HEAD abc123",
        "branch refs/heads/main",
        "",
        "worktree /home/user/project-wt1",
        "HEAD def456",
        "branch refs/heads/feat/issue-42-login",
        "",
      }, "\n")

      local result = wt.parse_porcelain(output)
      assert.equals(2, #result)
      assert.equals("feat/issue-42-login", result[2].branch)
    end)

    it("handles bare worktree", function()
      local output = table.concat({
        "worktree /home/user/project.git",
        "HEAD abc123",
        "bare",
        "",
      }, "\n")

      local result = wt.parse_porcelain(output)
      assert.equals(1, #result)
      assert.is_true(result[1].bare)
      assert.is_nil(result[1].branch)
    end)

    it("handles detached HEAD", function()
      local output = table.concat({
        "worktree /home/user/project-wt",
        "HEAD abc123",
        "detached",
        "",
      }, "\n")

      local result = wt.parse_porcelain(output)
      assert.equals(1, #result)
      assert.is_true(result[1].detached)
    end)

    it("returns empty for empty input", function()
      assert.equals(0, #wt.parse_porcelain(""))
    end)

    it("returns empty for nil input", function()
      assert.equals(0, #wt.parse_porcelain(nil))
    end)

    it("strips refs/heads/ prefix from branch", function()
      local output = "worktree /path\nHEAD abc\nbranch refs/heads/feat/issue-7-fix\n\n"
      local result = wt.parse_porcelain(output)
      assert.equals("feat/issue-7-fix", result[1].branch)
    end)
  end)

  describe("map_to_issues", function()
    it("maps worktrees to issue numbers via branch name", function()
      local worktrees = {
        { path = "/main", branch = "main" },
        { path = "/wt1", branch = "feat/issue-42-login" },
        { path = "/wt2", branch = "fix/issue-7-null" },
      }

      local map = wt.map_to_issues(worktrees)
      assert.is_not_nil(map[42])
      assert.equals("/wt1", map[42].path)
      assert.is_not_nil(map[7])
      assert.equals("/wt2", map[7].path)
      assert.is_nil(map[1]) -- main has no issue number
    end)

    it("skips bare worktrees", function()
      local worktrees = {
        { path = "/bare", branch = "feat/issue-42", bare = true },
      }

      local map = wt.map_to_issues(worktrees)
      assert.is_nil(map[42])
    end)

    it("skips worktrees without branch", function()
      local worktrees = {
        { path = "/detached", detached = true },
      }

      local map = wt.map_to_issues(worktrees)
      -- Should have no entries
      local count = 0
      for _ in pairs(map) do
        count = count + 1
      end
      assert.equals(0, count)
    end)

    it("returns empty map for empty input", function()
      local map = wt.map_to_issues({})
      local count = 0
      for _ in pairs(map) do
        count = count + 1
      end
      assert.equals(0, count)
    end)
  end)

  describe("fetch_worktree_map", function()
    it("parses git worktree list output", function()
      helpers.mock_vim_system({
        {
          code = 0,
          stdout = table.concat({
            "worktree /home/user/project",
            "HEAD abc",
            "branch refs/heads/main",
            "",
            "worktree /home/user/wt-42",
            "HEAD def",
            "branch refs/heads/feat/issue-42-login",
            "",
          }, "\n"),
        },
      })

      local map = wt.fetch_worktree_map()
      assert.is_not_nil(map[42])
      assert.equals("/home/user/wt-42", map[42].path)
    end)

    it("returns empty map on git error", function()
      helpers.mock_vim_system({
        { code = 128, stderr = "not a git repo" },
      })

      local map = wt.fetch_worktree_map()
      local count = 0
      for _ in pairs(map) do
        count = count + 1
      end
      assert.equals(0, count)
    end)
  end)

  describe("check_dirty", function()
    it("reports dirty when status has output", function()
      helpers.mock_vim_system({
        { code = 0, stdout = " M file.lua\n" },
      })

      local done = false
      local result = nil
      wt.check_dirty("/some/path", function(dirty)
        done = true
        result = dirty
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(result)
    end)

    it("reports clean when status is empty", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "" },
      })

      local done = false
      local result = nil
      wt.check_dirty("/some/path", function(dirty)
        done = true
        result = dirty
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result)
    end)

    it("reports clean on git error", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "error" },
      })

      local done = false
      local result = nil
      wt.check_dirty("/some/path", function(dirty)
        done = true
        result = dirty
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result)
    end)
  end)
end)

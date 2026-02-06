local helpers = require("tests.helpers")

describe("okuban.api", function()
  local api, config

  before_each(function()
    package.loaded["okuban.api"] = nil
    package.loaded["okuban.config"] = nil
    config = require("okuban.config")
    api = require("okuban.api")
    api._reset_preflight()
  end)

  after_each(function()
    helpers.restore_vim_system()
  end)

  describe("check_gh_installed", function()
    it("returns true when gh is on PATH", function()
      -- gh is installed in CI and dev environments
      -- This is a real check, not mocked
      local result = api.check_gh_installed()
      assert.is_true(result)
    end)
  end)

  describe("check_gh_auth", function()
    it("calls callback with true when authenticated", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "Logged in to github.com" },
      })

      local done = false
      local success = false
      api.check_gh_auth(function(ok)
        done = true
        success = ok
      end)

      -- Force scheduled callbacks to run
      vim.wait(1000, function()
        return done
      end)
      assert.is_true(success)
    end)

    it("calls callback with false when not authenticated", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "not logged in" },
      })

      local done = false
      local success = true
      local err_msg = nil
      api.check_gh_auth(function(ok, err)
        done = true
        success = ok
        err_msg = err
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_false(success)
      assert.truthy(err_msg:match("gh auth login"))
    end)
  end)

  describe("check_repo_access", function()
    it("calls callback with true when repo is accessible", function()
      helpers.mock_vim_system({
        { code = 0, stdout = "okuban.nvim\n" },
      })

      local done = false
      local success = false
      api.check_repo_access(function(ok)
        done = true
        success = ok
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_true(success)
    end)

    it("calls callback with false when repo is not accessible", function()
      helpers.mock_vim_system({
        { code = 1, stderr = "not a git repository" },
      })

      local done = false
      local success = true
      api.check_repo_access(function(ok)
        done = true
        success = ok
      end)

      vim.wait(1000, function()
        return done
      end)
      assert.is_false(success)
    end)
  end)

  describe("preflight", function()
    it("skips all checks when skip_preflight is true", function()
      config.setup({ skip_preflight = true })
      -- Re-require api to pick up new config
      package.loaded["okuban.api"] = nil
      api = require("okuban.api")

      local done = false
      local success = false
      api.preflight(function(ok)
        done = true
        success = ok
      end)

      -- skip_preflight is synchronous, no need for vim.wait
      assert.is_true(done)
      assert.is_true(success)
    end)

    it("caches results after first successful preflight", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "Logged in" }, -- auth check
        { code = 0, stdout = "okuban.nvim\n" }, -- repo check
      })

      local done = false
      api.preflight(function(ok)
        done = true
        assert.is_true(ok)
      end)

      vim.wait(1000, function()
        return done
      end)

      -- Second call should not trigger any vim.system calls
      local done2 = false
      api.preflight(function(ok)
        done2 = true
        assert.is_true(ok)
      end)

      assert.is_true(done2)
      assert.equals(2, #calls) -- only 2 calls total, not 4
    end)

    it("runs auth and repo checks in sequence", function()
      local calls = helpers.mock_vim_system({
        { code = 0, stdout = "Logged in" }, -- auth
        { code = 0, stdout = "okuban.nvim\n" }, -- repo
      })

      local done = false
      api.preflight(function(ok)
        done = true
        assert.is_true(ok)
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(2, #calls)
      -- First call should be auth status
      assert.truthy(vim.tbl_contains(calls[1].cmd, "auth"))
      -- Second call should be repo view
      assert.truthy(vim.tbl_contains(calls[2].cmd, "repo"))
    end)

    it("stops on auth failure without checking repo", function()
      local calls = helpers.mock_vim_system({
        { code = 1, stderr = "not logged in" }, -- auth fails
      })

      local done = false
      api.preflight(function(ok)
        done = true
        assert.is_false(ok)
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.equals(1, #calls) -- only auth was called
    end)
  end)

  describe("github_hostname", function()
    it("includes hostname in gh commands when configured", function()
      config.setup({ github_hostname = "github.example.com" })
      package.loaded["okuban.api"] = nil
      api = require("okuban.api")

      local cmd = api._gh_base_cmd()
      assert.equals("gh", cmd[1])
      assert.equals("--hostname", cmd[2])
      assert.equals("github.example.com", cmd[3])
    end)

    it("uses plain gh when no hostname configured", function()
      config.setup({})
      package.loaded["okuban.api"] = nil
      api = require("okuban.api")

      local cmd = api._gh_base_cmd()
      assert.equals(1, #cmd)
      assert.equals("gh", cmd[1])
    end)
  end)
end)

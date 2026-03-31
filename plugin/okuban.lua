if vim.g.loaded_okuban then
  return
end
vim.g.loaded_okuban = true

vim.api.nvim_create_user_command("Okuban", function()
  require("okuban").open()
end, { desc = "Open okuban kanban board" })

vim.api.nvim_create_user_command("OkubanClose", function()
  require("okuban").close()
end, { desc = "Close okuban kanban board" })

vim.api.nvim_create_user_command("OkubanRefresh", function()
  require("okuban").refresh()
end, { desc = "Refresh okuban kanban board" })

vim.api.nvim_create_user_command("OkubanSetup", function(cmd)
  local full = cmd.args == "--full"
  require("okuban").setup_labels({ full = full })
end, { desc = "Create okuban labels on the repo", nargs = "?" })

vim.api.nvim_create_user_command("OkubanSource", function(cmd)
  local args = vim.split(cmd.args, "%s+", { trimempty = true })
  local source = args[1]
  local number = args[2] and tonumber(args[2]) or nil
  if not source then
    local current = require("okuban.config").get().source
    vim.notify("okuban: current source = " .. current, vim.log.levels.INFO)
    return
  end
  require("okuban").set_source(source, number)
end, { desc = "Switch okuban data source (labels or project)", nargs = "?" })

vim.api.nvim_create_user_command("OkubanTriage", function()
  require("okuban.api").preflight(function(ok)
    if not ok then
      return
    end
    require("okuban.triage").run()
  end)
end, { desc = "Triage existing issues into okuban kanban columns" })

vim.api.nvim_create_user_command("OkubanPopup", function()
  require("okuban").open_popup()
end, { desc = "Open okuban kanban board in a tmux display-popup" })

vim.api.nvim_create_user_command("OkubanMigrate", function(cmd)
  local args = vim.split(cmd.args, "%s+", { trimempty = true })
  local target = args[1]
  local number = args[2] and tonumber(args[2]) or nil
  if target ~= "project" then
    vim.notify("okuban: usage: OkubanMigrate project [number]", vim.log.levels.ERROR)
    return
  end
  require("okuban").migrate_to_project(number)
end, { desc = "Migrate label board into a GitHub Project", nargs = "+" })

-- In popup mode (OKUBAN_POPUP=1): suppress the intro screen and open the board at
-- VimEnter time. This fires before any -c commands and before dashboard plugins,
-- so the user sees the board immediately when the popup window appears.
if vim.env.OKUBAN_POPUP == "1" then
  vim.opt.shortmess:append("I")
  -- Disable dashboard-nvim so it doesn't flash before the board appears
  vim.g.loaded_dashboard = 1
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    nested = true,
    callback = function()
      -- vim.schedule lets lazy.nvim finish its final setup pass before we open
      vim.schedule(function()
        require("okuban").open()
      end)
    end,
  })
end

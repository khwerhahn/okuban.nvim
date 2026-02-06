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

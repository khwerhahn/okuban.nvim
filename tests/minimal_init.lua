-- Minimal init for running tests in headless mode
-- Usage: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if not vim.uv.fs_stat(plenary_path) then
  plenary_path = vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim"
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_path)

vim.cmd("runtime plugin/plenary.vim")

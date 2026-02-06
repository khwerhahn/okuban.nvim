local M = {}

---@class OkubanColumn
---@field label string
---@field name string
---@field color string
---@field state string|nil "open", "closed", or "all" (default: "open")
---@field limit integer|nil Max issues to fetch (default: 100)

---@class OkubanKeymaps
---@field column_left string
---@field column_right string
---@field card_up string
---@field card_down string
---@field move_card string
---@field open_actions string
---@field goto_current string
---@field close string
---@field refresh string
---@field help string

---@class OkubanClaudeConfig
---@field enabled boolean
---@field max_budget_usd number
---@field max_turns integer

---@class OkubanConfig
---@field columns OkubanColumn[]
---@field show_unsorted boolean
---@field skip_preflight boolean
---@field github_hostname string|nil
---@field preview_lines integer Height of preview pane below board (0 to disable, default: 8)
---@field show_tldr boolean Show TLDR in preview pane from issue body (default: true)
---@field poll_interval integer Auto-refresh interval in seconds (0 to disable, default: 20)
---@field keymaps OkubanKeymaps
---@field claude OkubanClaudeConfig

---@type OkubanConfig
local defaults = {
  columns = {
    { label = "okuban:backlog", name = "Backlog", color = "#c5def5" },
    { label = "okuban:todo", name = "Todo", color = "#0075ca" },
    { label = "okuban:in-progress", name = "In Progress", color = "#fbca04" },
    { label = "okuban:review", name = "Review", color = "#d4c5f9" },
    { label = "okuban:done", name = "Done", color = "#0e8a16", state = "all", limit = 20 },
  },
  show_unsorted = true,
  skip_preflight = false,
  github_hostname = nil,
  preview_lines = 8,
  show_tldr = true,
  poll_interval = 20,
  keymaps = {
    column_left = "h",
    column_right = "l",
    card_up = "k",
    card_down = "j",
    move_card = "m",
    open_actions = "<CR>",
    goto_current = "g",
    close = "q",
    refresh = "r",
    help = "?",
  },
  claude = {
    enabled = true,
    max_budget_usd = 5.00,
    max_turns = 30,
  },
}

---@type OkubanConfig
local config = vim.deepcopy(defaults)

--- Deep merge user options into defaults.
---@param user_opts table|nil
function M.setup(user_opts)
  config = vim.deepcopy(defaults)
  if user_opts then
    config = vim.tbl_deep_extend("force", config, user_opts)
  end
end

--- Get the current config.
---@return OkubanConfig
function M.get()
  return config
end

--- Get default config (for tests/reference).
---@return OkubanConfig
function M.defaults()
  return vim.deepcopy(defaults)
end

return M

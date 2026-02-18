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
---@field new_issue string
---@field close string
---@field refresh string
---@field help string

---@class OkubanAgentTeamsConfig
---@field enabled boolean EXPERIMENTAL: Enable agent teams (default: false)
---@field teammate_mode "tmux"|"auto" Teammate mode (default: "tmux")

---@class OkubanClaudeConfig
---@field enabled boolean
---@field max_budget_usd number
---@field max_turns integer
---@field model string|nil Override Claude model (e.g. "sonnet", "opus")
---@field launch_mode "headless"|"tmux" Launch mode: "headless" (jobstart) or "tmux" (new window)
---@field allowed_tools string[]
---@field worktree_base_dir string|nil
---@field auto_push boolean
---@field auto_pr boolean
---@field agent_teams OkubanAgentTeamsConfig

---@class OkubanProjectConfig
---@field number integer|nil Project number (nil = show picker on first :Okuban)
---@field owner string|nil Project owner (nil = auto-detect from repo)
---@field done_limit integer Max items to show per column (default: 20)

---@class OkubanGlobalKeymaps
---@field open string|false
---@field close string|false
---@field refresh string|false
---@field setup string|false
---@field setup_full string|false
---@field source_labels string|false
---@field source_project string|false
---@field migrate string|false

---@class OkubanTriageConfig
---@field enabled boolean Enable auto-triage after label setup (default: true)
---@field include_closed boolean Include closed issues in triage (default: true)
---@field ai_enabled boolean Allow AI-assisted triage via Claude CLI (default: true)

---@class OkubanConfig
---@field source "labels"|"project" Data source: "labels" (default) or "project"
---@field columns OkubanColumn[]
---@field project OkubanProjectConfig
---@field show_unsorted boolean
---@field skip_preflight boolean
---@field github_hostname string|nil
---@field preview_lines integer Height of preview pane below board (0 to disable, default: 8)
---@field show_tldr boolean Show TLDR in preview pane from issue body (default: true)
---@field poll_interval integer Auto-refresh interval in seconds (0 to disable, default: 20)
---@field initial_fetch_limit integer Initial issues per column (default: 10, 0 to disable lazy loading)
---@field keymaps OkubanKeymaps
---@field global_keymaps OkubanGlobalKeymaps
---@field claude OkubanClaudeConfig
---@field triage OkubanTriageConfig

---@type OkubanConfig
local defaults = {
  columns = {
    { label = "okuban:backlog", name = "Backlog", color = "#c5def5" },
    { label = "okuban:todo", name = "Todo", color = "#0075ca" },
    { label = "okuban:in-progress", name = "In Progress", color = "#fbca04" },
    { label = "okuban:review", name = "Review", color = "#d4c5f9" },
    { label = "okuban:done", name = "Done", color = "#0e8a16", state = "all", limit = 20 },
  },
  source = "labels",
  project = {
    number = nil,
    owner = nil,
    done_limit = 20,
  },
  show_unsorted = true,
  skip_preflight = false,
  github_hostname = nil,
  preview_lines = 8,
  show_tldr = true,
  poll_interval = 20,
  initial_fetch_limit = 10,
  keymaps = {
    column_left = "h",
    column_right = "l",
    card_up = "k",
    card_down = "j",
    move_card = "m",
    open_actions = "<CR>",
    goto_current = "g",
    new_issue = "n",
    close = "q",
    refresh = "r",
    help = "?",
  },
  global_keymaps = {
    open = "<leader>bb",
    close = "<leader>bq",
    refresh = "<leader>br",
    setup = "<leader>bs",
    setup_full = "<leader>bS",
    source_labels = "<leader>bl",
    source_project = "<leader>bp",
    migrate = "<leader>bm",
  },
  claude = {
    enabled = true,
    max_budget_usd = 5.00,
    max_turns = 30,
    model = nil,
    launch_mode = "headless",
    allowed_tools = {
      "Bash(git:*)",
      "Bash(gh:*)",
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
    },
    worktree_base_dir = nil,
    auto_push = false,
    auto_pr = false,
    agent_teams = {
      enabled = false,
      teammate_mode = "tmux",
    },
  },
  triage = {
    enabled = true,
    include_closed = true,
    ai_enabled = true,
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

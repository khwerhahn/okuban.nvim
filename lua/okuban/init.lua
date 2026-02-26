local M = {}

local config = require("okuban.config")
local utils = require("okuban.utils")
local api = require("okuban.api")

--- Set up okuban with user options.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  M._register_global_keymaps()
end

--- Register global keymaps from config. Keys set to false are skipped.
function M._register_global_keymaps()
  local gk = config.get().global_keymaps
  local map = {
    { key = gk.open, cmd = "<cmd>Okuban<cr>", desc = "Open kanban board" },
    { key = gk.close, cmd = "<cmd>OkubanClose<cr>", desc = "Close kanban board" },
    { key = gk.refresh, cmd = "<cmd>OkubanRefresh<cr>", desc = "Refresh kanban board" },
    { key = gk.setup, cmd = "<cmd>OkubanSetup<cr>", desc = "Create kanban labels" },
    { key = gk.setup_full, cmd = "<cmd>OkubanSetup --full<cr>", desc = "Create all kanban labels" },
    { key = gk.source_labels, cmd = "<cmd>OkubanSource labels<cr>", desc = "Switch to label source" },
    { key = gk.source_project, cmd = "<cmd>OkubanSource project<cr>", desc = "Switch to project source" },
    { key = gk.migrate, cmd = "<cmd>OkubanMigrate project<cr>", desc = "Migrate labels to project" },
  }
  for _, m in ipairs(map) do
    if m.key and m.key ~= false then
      vim.keymap.set("n", m.key, m.cmd, { desc = m.desc })
    end
  end
end

--- Restore saved per-repo state into the live config.
--- Tracked per-repo-root so switching repos in the same session works.
local _state_loaded_for = {} ---@type table<string, boolean>
function M._load_saved_state()
  local _, key = utils.state_file_path()
  if key == "" then
    return -- not inside a git repo
  end
  if _state_loaded_for[key] then
    return
  end
  _state_loaded_for[key] = true
  local state = utils.load_state()
  if not state then
    return
  end
  local cfg = config.get()
  if state.source then
    cfg.source = state.source
  end
  if state.project_number then
    cfg.project.number = state.project_number
  end
  if state.project_owner then
    cfg.project.owner = state.project_owner
  end
end

--- Open the kanban board.
function M.open()
  -- Restore saved per-repo state on first open
  M._load_saved_state()

  local Board = require("okuban.ui.board")
  local board = Board.get_instance()

  -- If board is already open, close it first (toggle behavior)
  if board:is_open() then
    board:close()
    return
  end

  api.preflight(function(ok)
    if not ok then
      return
    end

    -- For project mode: ensure scope + project selection before opening
    local cfg = config.get()
    if cfg.source == "project" and not cfg.project.number then
      api.check_project_scope(function(scope_ok, scope_err)
        if not scope_ok then
          utils.notify(scope_err, vim.log.levels.ERROR)
          return
        end
        M._pick_project(function(number)
          if not number then
            return
          end
          cfg.project.number = number
          -- Persist the project selection
          utils.save_state({
            source = "project",
            project_number = number,
            project_owner = cfg.project.owner,
          })
          -- Now open the board with the selected project
          board:open_loading()
          M._open_board(board)
        end)
      end)
      return
    end

    -- Show loading skeleton instantly, populate when data arrives
    board:open_loading()
    M._open_board(board)
  end)
end

local CACHE_MAX_AGE = 3600 -- 1 hour

--- Populate board with data and run first-open checks.
---@param board table Board instance
---@param data table Board data from api.fetch_all_columns
---@param skip_focus boolean If true, skip auto-focus (used for cached data)
function M._populate_board(board, data, skip_focus)
  board:populate(data)

  -- First-open hint: if all kanban columns empty but unsorted has issues
  if not board._hint_shown then
    board._hint_shown = true
    local all_empty = true
    for _, col in ipairs(data.columns) do
      if #col.issues > 0 then
        all_empty = false
        break
      end
    end
    if all_empty and data.unsorted and #data.unsorted > 0 then
      utils.notify("Tip: press Enter on a card to triage it into a column, or m to move it directly")
    end
  end

  -- Auto-focus: detect current issue and navigate to it
  if not skip_focus then
    local detect = require("okuban.detect")
    detect.detect_issue(function(issue_number)
      if not issue_number or not board:is_open() or not board.navigation then
        return
      end
      board.navigation:focus_issue(issue_number)
    end)
  end
end

--- Fetch data and populate an already-opened loading board.
--- If cached data is available (< 1h old), shows it instantly and refreshes in background.
---@param board table Board instance (already showing loading skeleton)
function M._open_board(board)
  -- Try cached data first for instant display
  local cached = api.get_cached_board_data(CACHE_MAX_AGE)
  if cached then
    M._populate_board(board, cached, false)
    -- Refresh immediately in background, then start limited auto-refresh cycle
    api.fetch_all_columns(function(data)
      if data and board:is_open() then
        board:refresh(data)
        board:_start_auto_refresh()
      end
    end)
    return
  end

  -- No cache — fetch fresh (loading skeleton already visible)
  api.fetch_all_columns(function(data)
    if not data then
      utils.notify("Failed to fetch issues", vim.log.levels.ERROR)
      board:close()
      return
    end
    M._populate_board(board, data, false)
    board:_start_auto_refresh()
  end)
end

--- Close the kanban board.
function M.close()
  local Board = require("okuban.ui.board")
  Board.close_instance()
end

--- Refresh the kanban board.
function M.refresh()
  local Board = require("okuban.ui.board")
  local board = Board.get_instance()
  if not board:is_open() then
    utils.notify("Board not open", vim.log.levels.WARN)
    return
  end
  local stop = utils.spinner_start("Refreshing board...")
  api.fetch_all_columns(function(data)
    if not data then
      stop("Failed to refresh")
      return
    end
    stop()
    board:refresh(data)
    board:_start_auto_refresh()
  end)
end

--- Run label setup on the current repo.
---@param opts { full: boolean }
function M.setup_labels(opts)
  api.preflight(function(ok)
    if not ok then
      return
    end
    local full = opts and opts.full or false
    utils.notify("Creating labels" .. (full and " (full set)" or "") .. "...")
    api.create_all_labels(full, function(created, failed)
      local msg = failed > 0 and string.format("Created %d labels, %d failed", created, failed)
        or string.format("Created %d labels", created)
      utils.notify(msg, failed > 0 and vim.log.levels.WARN or nil)

      -- Auto-triage existing issues after label creation
      local cfg = config.get()
      if cfg.triage.enabled then
        require("okuban.triage").run()
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Source switching
-- ---------------------------------------------------------------------------

--- Switch the board data source at runtime.
---@param source "labels"|"project"
---@param project_number integer|nil
function M.set_source(source, project_number)
  if source ~= "labels" and source ~= "project" then
    utils.notify("Invalid source: " .. tostring(source) .. '. Use "labels" or "project".', vim.log.levels.ERROR)
    return
  end

  local function apply_source()
    -- Update the live config for the session
    local cfg = config.get()
    cfg.source = source

    if source == "project" and project_number then
      cfg.project.number = project_number
    end

    -- Persist source choice for this repo
    utils.save_state({
      source = source,
      project_number = cfg.project.number,
      project_owner = cfg.project.owner,
    })

    -- Reset project cache when switching sources
    local api_project = require("okuban.api_project")
    api_project.reset_cache()

    -- Close and reopen the board if it's open
    local Board = require("okuban.ui.board")
    local board = Board.get_instance()
    if board:is_open() then
      board:close()
      M.open()
    else
      utils.notify("Source set to " .. source)
    end
  end

  local stop = utils.spinner_start("Switching to " .. source .. "...")
  if source == "project" then
    -- Check project scope first
    api.check_project_scope(function(ok, err)
      if not ok then
        stop(err)
        return
      end

      if project_number then
        stop("Source set to " .. source)
        apply_source()
      else
        stop()
        -- Show project picker
        M._pick_project(function(number)
          if number then
            project_number = number
            apply_source()
          end
        end)
      end
    end)
  else
    stop("Source set to " .. source)
    apply_source()
  end
end

--- Show a project picker using vim.ui.select.
---@param callback fun(number: integer|nil)
function M._pick_project(callback)
  local api_project = require("okuban.api_project")
  local stop = utils.spinner_start("Loading projects...")

  -- Detect owner
  api_project.detect_owner(function(owner)
    if not owner then
      stop("Could not detect repository owner")
      callback(nil)
      return
    end

    -- Update config with detected owner
    config.get().project.owner = owner

    -- List projects
    api_project.list_projects(owner, function(projects, err)
      if err or not projects then
        stop(err or "Failed to list projects")
        callback(nil)
        return
      end

      if #projects == 0 then
        stop("No projects found for " .. owner)
        callback(nil)
        return
      end

      stop()

      local picker = require("okuban.ui.picker")
      picker.select(projects, {
        prompt = "Select a GitHub Project",
        format_item = function(p)
          return string.format("#%d: %s", p.number, p.title)
        end,
      }, function(project)
        if not project then
          callback(nil)
          return
        end
        callback(project.number)
      end)
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Migration
-- ---------------------------------------------------------------------------

--- Migrate label-based board positions into a GitHub Project.
--- For each issue on the label board, adds it to the project and sets the
--- Status field to match the column the issue is currently in.
---@param project_number integer|nil If nil, shows picker
function M.migrate_to_project(project_number)
  api.preflight(function(ok)
    if not ok then
      return
    end

    -- Check project scope
    api.check_project_scope(function(scope_ok, scope_err)
      if not scope_ok then
        utils.notify(scope_err, vim.log.levels.ERROR)
        return
      end

      local function do_migrate(number)
        local stop_migrate = utils.spinner_start("Preparing migration...")
        local api_project = require("okuban.api_project")

        -- Detect owner if not already set
        local cfg = config.get()
        local owner = cfg.project.owner

        local function with_owner(detected_owner)
          if not detected_owner then
            stop_migrate("Could not detect repository owner")
            return
          end

          utils.spinner_update("Fetching current board...")
          -- Fetch current label-based board
          require("okuban.api_labels").fetch_all_columns(function(board_data)
            if not board_data then
              stop_migrate("Failed to fetch current board")
              return
            end

            utils.spinner_update("Fetching project fields...")
            -- Fetch the target project's Status field
            api_project.fetch_status_field(number, detected_owner, function(field, field_err)
              if field_err or not field then
                stop_migrate(field_err or "Failed to fetch project fields")
                return
              end

              -- Build option name → option ID lookup (case-insensitive)
              local option_map = {}
              for _, opt in ipairs(field.options) do
                option_map[opt.name:lower()] = opt.id
              end

              utils.spinner_update("Resolving project ID...")
              -- Resolve project ID for item-edit
              api_project.resolve_project_id(number, detected_owner, function(project_id, id_err)
                if id_err or not project_id then
                  stop_migrate(id_err or "Failed to resolve project ID")
                  return
                end

                -- Get repo URL for item-add
                local repo_cmd = vim.list_extend(vim.deepcopy(api._gh_base_cmd()), {
                  "repo",
                  "view",
                  "--json",
                  "url",
                  "-q",
                  ".url",
                })
                vim.system(repo_cmd, { text = true }, function(repo_result)
                  vim.schedule(function()
                    local repo_url = vim.trim(repo_result.stdout or "")
                    if repo_url == "" then
                      stop_migrate("Could not detect repository URL")
                      return
                    end

                    -- Count issues to migrate
                    local total = 0
                    for _, col in ipairs(board_data.columns) do
                      total = total + #col.issues
                    end

                    if total == 0 then
                      stop_migrate("No issues to migrate")
                      return
                    end

                    utils.spinner_update(string.format("Migrating 0/%d issues...", total))

                    local migrated = 0
                    local failed = 0
                    local pending = total

                    local function on_complete()
                      pending = pending - 1
                      local done = migrated + failed
                      if pending > 0 then
                        utils.spinner_update(string.format("Migrating %d/%d issues...", done + 1, total))
                      else
                        if failed > 0 then
                          stop_migrate(string.format("Migrated %d issues, %d failed", migrated, failed))
                        else
                          stop_migrate(string.format("Migrated %d issues to project #%d", migrated, number))
                        end
                      end
                    end

                    for _, col in ipairs(board_data.columns) do
                      local target_option_id = option_map[col.name:lower()]
                      for _, issue in ipairs(col.issues) do
                        local issue_url = repo_url .. "/issues/" .. issue.number
                        api_project.add_item(issue_url, number, detected_owner, function(item_id, add_err)
                          if add_err then
                            failed = failed + 1
                            on_complete()
                            return
                          end
                          if item_id and target_option_id then
                            api_project.move_item(item_id, project_id, field.id, target_option_id, function(move_ok)
                              if move_ok then
                                migrated = migrated + 1
                              else
                                failed = failed + 1
                              end
                              on_complete()
                            end)
                          else
                            -- Added but couldn't set status (no matching column or no item ID)
                            migrated = migrated + 1
                            on_complete()
                          end
                        end)
                      end
                    end
                  end)
                end)
              end)
            end)
          end)
        end

        if owner then
          with_owner(owner)
        else
          api_project.detect_owner(function(detected)
            with_owner(detected)
          end)
        end
      end

      if project_number then
        do_migrate(project_number)
      else
        M._pick_project(function(number)
          if number then
            do_migrate(number)
          end
        end)
      end
    end)
  end)
end

return M

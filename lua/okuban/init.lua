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

--- Open the kanban board.
function M.open()
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

--- Fetch data and populate an already-opened loading board.
---@param board table Board instance (already showing loading skeleton)
function M._open_board(board)
  api.fetch_all_columns(function(data)
    if not data then
      utils.notify("Failed to fetch issues", vim.log.levels.ERROR)
      board:close()
      return
    end
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
    local detect = require("okuban.detect")
    detect.detect_issue(function(issue_number)
      if not issue_number or not board:is_open() or not board.navigation then
        return
      end
      local found = board.navigation:focus_issue(issue_number)
      if found then
        local issue = board.navigation:get_selected_issue()
        local title = issue and issue.title or ""
        utils.notify("Focused on #" .. issue_number .. ": " .. title)
      end
    end)
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
  api.fetch_all_columns(function(data)
    if not data then
      utils.notify("Failed to refresh", vim.log.levels.ERROR)
      return
    end
    board:refresh(data)
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
      if failed > 0 then
        utils.notify(string.format("Created %d labels, %d failed", created, failed), vim.log.levels.WARN)
      else
        utils.notify(string.format("Created %d labels", created))
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

  if source == "project" then
    -- Check project scope first
    api.check_project_scope(function(ok, err)
      if not ok then
        utils.notify(err, vim.log.levels.ERROR)
        return
      end

      if project_number then
        apply_source()
      else
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
    apply_source()
  end
end

--- Show a project picker using vim.ui.select.
---@param callback fun(number: integer|nil)
function M._pick_project(callback)
  local api_project = require("okuban.api_project")

  -- Detect owner
  api_project.detect_owner(function(owner)
    if not owner then
      utils.notify("Could not detect repository owner", vim.log.levels.ERROR)
      callback(nil)
      return
    end

    -- Update config with detected owner
    config.get().project.owner = owner

    -- List projects
    api_project.list_projects(owner, function(projects, err)
      if err or not projects then
        utils.notify(err or "Failed to list projects", vim.log.levels.ERROR)
        callback(nil)
        return
      end

      if #projects == 0 then
        utils.notify("No projects found for " .. owner, vim.log.levels.WARN)
        callback(nil)
        return
      end

      -- Build display list
      local items = {}
      for _, p in ipairs(projects) do
        table.insert(items, string.format("#%d: %s", p.number, p.title))
      end

      vim.ui.select(items, { prompt = "Select a GitHub Project:" }, function(choice)
        if not choice then
          callback(nil)
          return
        end

        -- Find the selected project
        for i, item in ipairs(items) do
          if item == choice then
            callback(projects[i].number)
            return
          end
        end
        callback(nil)
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
        local api_project = require("okuban.api_project")

        -- Detect owner if not already set
        local cfg = config.get()
        local owner = cfg.project.owner

        local function with_owner(detected_owner)
          if not detected_owner then
            utils.notify("Could not detect repository owner", vim.log.levels.ERROR)
            return
          end

          -- Fetch current label-based board
          require("okuban.api_labels").fetch_all_columns(function(board_data)
            if not board_data then
              utils.notify("Failed to fetch current board", vim.log.levels.ERROR)
              return
            end

            -- Fetch the target project's Status field
            api_project.fetch_status_field(number, detected_owner, function(field, field_err)
              if field_err or not field then
                utils.notify(field_err or "Failed to fetch project fields", vim.log.levels.ERROR)
                return
              end

              -- Build option name → option ID lookup (case-insensitive)
              local option_map = {}
              for _, opt in ipairs(field.options) do
                option_map[opt.name:lower()] = opt.id
              end

              -- Resolve project ID for item-edit
              api_project.resolve_project_id(number, detected_owner, function(project_id, id_err)
                if id_err or not project_id then
                  utils.notify(id_err or "Failed to resolve project ID", vim.log.levels.ERROR)
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
                      utils.notify("Could not detect repository URL", vim.log.levels.ERROR)
                      return
                    end

                    -- Count issues to migrate
                    local total = 0
                    for _, col in ipairs(board_data.columns) do
                      total = total + #col.issues
                    end

                    if total == 0 then
                      utils.notify("No issues to migrate", vim.log.levels.WARN)
                      return
                    end

                    utils.notify(string.format("Migrating %d issues to project #%d...", total, number))

                    local migrated = 0
                    local failed = 0
                    local pending = total

                    local function on_complete()
                      pending = pending - 1
                      if pending == 0 then
                        if failed > 0 then
                          utils.notify(
                            string.format("Migrated %d issues, %d failed", migrated, failed),
                            vim.log.levels.WARN
                          )
                        else
                          utils.notify(string.format("Migrated %d issues to project #%d", migrated, number))
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

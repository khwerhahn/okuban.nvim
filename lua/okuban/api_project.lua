local utils = require("okuban.utils")

local M = {}

--- Session-level cache for project metadata.
local cache = {
  project_id = nil, -- node ID (string), fetched once
  column_field_name = nil, -- name of the field used for board columns (e.g. "Status", "Workflow Stage")
  status_field = nil, -- { id, options = [{ id, name }] }, fetched once
  item_map = {}, -- issue_number → item_node_id, rebuilt each fetch
  board_data = nil, -- last fetched board data, survives board close/reopen
  board_data_ts = 0, -- os.time() when board_data was last stored
  full_buckets = nil, -- full issue sets per option ID for expand
}

--- Get the gh base command from the shared api module.
---@return string[]
local function gh_base_cmd()
  return require("okuban.api")._gh_base_cmd()
end

--- Detect the repo owner (user or org) from git remote.
---@param callback fun(owner: string|nil)
function M.detect_owner(callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "repo",
    "view",
    "--json",
    "owner",
    "-q",
    ".owner.login",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 and result.stdout then
        local owner = vim.trim(result.stdout)
        if owner ~= "" then
          callback(owner)
          return
        end
      end
      callback(nil)
    end)
  end)
end

--- List projects for the given owner.
---@param owner string
---@param callback fun(projects: table[]|nil, err: string|nil)
function M.list_projects(owner, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "project",
    "list",
    "--owner",
    owner,
    "--format",
    "json",
    "--limit",
    "50",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to list projects: " .. (result.stderr or ""))
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or type(data) ~= "table" then
        callback({}, nil)
        return
      end
      -- gh project list --format json returns { projects: [...] }
      local projects = data.projects or data
      callback(projects, nil)
    end)
  end)
end

--- Resolve the project node ID from a project number.
---@param number integer
---@param owner string
---@param callback fun(project_id: string|nil, err: string|nil)
function M.resolve_project_id(number, owner, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "project",
    "view",
    tostring(number),
    "--owner",
    owner,
    "--format",
    "json",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to resolve project: " .. (result.stderr or ""))
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or type(data) ~= "table" then
        callback(nil, "Failed to parse project data")
        return
      end
      callback(data.id, nil)
    end)
  end)
end

--- Build the GraphQL query for detecting the column field from project views.
---@return string
local function build_views_query()
  return [[
query($projectId: ID!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      views(first: 10) {
        nodes {
          layout
          verticalGroupByFields(first: 1) {
            nodes {
              ... on ProjectV2SingleSelectField {
                name
              }
            }
          }
        }
      }
    }
  }
}]]
end

--- Detect the column field from the project's Board view configuration.
--- Falls back to "Status" if no Board view exists or no groupBy field is found.
---@param project_id string Project node ID
---@param callback fun(field_name: string)
function M.detect_column_field(project_id, callback)
  if cache.column_field_name then
    callback(cache.column_field_name)
    return
  end

  local query = build_views_query()
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "api",
    "graphql",
    "-f",
    "query=" .. query,
    "-F",
    "projectId=" .. project_id,
  })

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        cache.column_field_name = "Status"
        callback("Status")
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or type(data) ~= "table" then
        cache.column_field_name = "Status"
        callback("Status")
        return
      end

      local node = data.data and data.data.node
      local views = node and node.views and node.views.nodes
      if views then
        for _, view in ipairs(views) do
          if view.layout == "BOARD_LAYOUT" then
            local group_fields = view.verticalGroupByFields and view.verticalGroupByFields.nodes
            if group_fields and #group_fields > 0 and group_fields[1].name then
              cache.column_field_name = group_fields[1].name
              callback(group_fields[1].name)
              return
            end
          end
        end
      end

      -- No Board view or no groupBy field — default to Status
      cache.column_field_name = "Status"
      callback("Status")
    end)
  end)
end

--- Fetch a column field and its options from a project.
---@param number integer Project number
---@param owner string Project owner
---@param field_name string|nil Field name to search for (default: "Status")
---@param callback fun(field: table|nil, err: string|nil)
function M.fetch_column_field(number, owner, field_name, callback)
  -- Support old 3-arg call signature
  if type(field_name) == "function" then
    callback = field_name
    field_name = "Status"
  end
  field_name = field_name or "Status"

  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "project",
    "field-list",
    tostring(number),
    "--owner",
    owner,
    "--format",
    "json",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "Failed to fetch project fields: " .. (result.stderr or ""))
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or type(data) ~= "table" then
        callback(nil, "Failed to parse field data")
        return
      end
      -- gh project field-list returns { fields: [...] }
      local fields = data.fields or data
      for _, field in ipairs(fields) do
        if field.name == field_name then
          callback({
            id = field.id,
            options = field.options or {},
          }, nil)
          return
        end
      end
      callback(nil, "No '" .. field_name .. "' field found on project")
    end)
  end)
end

--- Backwards-compatible alias.
M.fetch_status_field = M.fetch_column_field

--- Build the GraphQL query for fetching project items with a column field.
---@param field_name string|nil Field name for column grouping (default: "Status")
---@return string
local function build_items_query(field_name)
  field_name = field_name or "Status"
  return "query($projectId: ID!, $cursor: String) {\n"
    .. "  node(id: $projectId) {\n"
    .. "    ... on ProjectV2 {\n"
    .. "      items(first: 100, after: $cursor) {\n"
    .. "        pageInfo { hasNextPage endCursor }\n"
    .. "        nodes {\n"
    .. "          id\n"
    .. '          fieldValueByName(name: "'
    .. field_name
    .. '") {\n'
    .. "            ... on ProjectV2ItemFieldSingleSelectValue {\n"
    .. "              name\n"
    .. "              optionId\n"
    .. "            }\n"
    .. "          }\n"
    .. "          content {\n"
    .. "            ... on Issue {\n"
    .. "              number title body state\n"
    .. "              assignees(first: 5) { nodes { login } }\n"
    .. "              labels(first: 10) { nodes { name color } }\n"
    .. "            }\n"
    .. "            ... on DraftIssue { title body }\n"
    .. "          }\n"
    .. "        }\n"
    .. "      }\n"
    .. "    }\n"
    .. "  }\n"
    .. "}"
end

--- Fetch project items via GraphQL (single page).
---@param project_id string Project node ID
---@param cursor string|nil Pagination cursor
---@param callback fun(items: table[]|nil, page_info: table|nil, err: string|nil)
function M.fetch_items_page(project_id, cursor, callback)
  local query = build_items_query(cache.column_field_name)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "api",
    "graphql",
    "-f",
    "query=" .. query,
    "-F",
    "projectId=" .. project_id,
  })
  if cursor then
    vim.list_extend(cmd, { "-F", "cursor=" .. cursor })
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, nil, "GraphQL query failed: " .. (result.stderr or ""))
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok or type(data) ~= "table" then
        callback(nil, nil, "Failed to parse GraphQL response")
        return
      end
      -- Navigate: data.data.node.items
      local node = data.data and data.data.node
      if not node or not node.items then
        callback(nil, nil, "Unexpected GraphQL response structure")
        return
      end
      callback(node.items.nodes or {}, node.items.pageInfo, nil)
    end)
  end)
end

--- Fetch all project items with automatic pagination.
---@param project_id string
---@param callback fun(items: table[]|nil, err: string|nil)
function M.fetch_all_items(project_id, callback)
  local all_items = {}

  local function fetch_page(cursor)
    M.fetch_items_page(project_id, cursor, function(items, page_info, err)
      if err then
        callback(nil, err)
        return
      end
      if items then
        vim.list_extend(all_items, items)
      end
      if page_info and page_info.hasNextPage and page_info.endCursor then
        fetch_page(page_info.endCursor)
      else
        callback(all_items, nil)
      end
    end)
  end

  fetch_page(nil)
end

--- Transform a raw GraphQL item into the standard issue format.
---@param item table Raw GraphQL item node
---@return table|nil issue Standardized issue, or nil for draft/invalid items
---@return string|nil status_option_id
local function transform_item(item)
  local content = item.content
  if not content or not content.number then
    return nil, nil -- draft issue or invalid
  end

  -- Extract assignees
  local assignees = {}
  if content.assignees and content.assignees.nodes then
    for _, a in ipairs(content.assignees.nodes) do
      table.insert(assignees, a)
    end
  end

  -- Extract labels
  local labels = {}
  if content.labels and content.labels.nodes then
    for _, l in ipairs(content.labels.nodes) do
      table.insert(labels, l)
    end
  end

  local issue = {
    number = content.number,
    title = content.title,
    body = content.body,
    state = content.state,
    assignees = assignees,
    labels = labels,
  }

  local status_option_id = nil
  if item.fieldValueByName and type(item.fieldValueByName) == "table" then
    status_option_id = item.fieldValueByName.optionId
  end

  return issue, status_option_id
end

--- Build board_data from items and status field options.
---@param items table[] Raw GraphQL items
---@param status_field table { id, options = [{ id, name }] }
---@param show_unsorted boolean
---@param done_limit integer
---@param initial_limit integer|nil Initial display cap per column (nil = use done_limit)
---@return table board_data
function M.build_board_data(items, status_field, show_unsorted, done_limit, initial_limit)
  -- Build column buckets keyed by option ID
  local buckets = {}
  for _, opt in ipairs(status_field.options) do
    buckets[opt.id] = {}
  end
  local unsorted_items = {}

  -- Rebuild item_map
  cache.item_map = {}

  for _, item in ipairs(items) do
    local issue, option_id = transform_item(item)
    if issue then
      cache.item_map[issue.number] = item.id
      if option_id and buckets[option_id] then
        table.insert(buckets[option_id], issue)
      else
        table.insert(unsorted_items, issue)
      end
    end
  end

  -- Store full buckets for expand
  cache.full_buckets = buckets

  -- Build columns in the order of status options
  local board_data = { columns = {} }
  for i, opt in ipairs(status_field.options) do
    local full_issues = buckets[opt.id] or {}
    -- Use initial_limit for first load, unless column was previously expanded
    local prev = cache.board_data and cache.board_data.columns[i]
    local cap = (prev and prev.expanded) and done_limit or (initial_limit or done_limit)
    local display = full_issues
    local has_more = false
    if cap and #full_issues > cap then
      display = {}
      for j = 1, cap do
        display[j] = full_issues[j]
      end
      has_more = true
    end
    table.insert(board_data.columns, {
      label = opt.id,
      name = opt.name,
      color = nil,
      issues = display,
      limit = done_limit,
      has_more = has_more,
      expanded = prev and prev.expanded or false,
    })
  end

  if show_unsorted then
    board_data.unsorted = unsorted_items
  end

  return board_data
end

--- Fetch all columns for project mode. Orchestrates ID resolution, field fetch,
--- and item fetch with session-level caching.
---@param callback fun(data: table|nil)
function M.fetch_all_columns(callback)
  local cfg = require("okuban.config").get()
  local proj = cfg.project
  local show_unsorted = cfg.show_unsorted

  local function with_project_id(project_id)
    cache.project_id = project_id

    local function with_column_field(field_name)
      cache.column_field_name = field_name

      local function with_status_field(status_field)
        cache.status_field = status_field
        M.fetch_all_items(project_id, function(items, err)
          if err then
            utils.notify(err, vim.log.levels.ERROR)
            callback(nil)
            return
          end
          local initial = cfg.initial_fetch_limit or 10
          local init_limit = initial > 0 and initial or nil
          local board_data = M.build_board_data(items, status_field, show_unsorted, proj.done_limit or 20, init_limit)
          cache.board_data = board_data
          cache.board_data_ts = os.time()
          callback(board_data)
        end)
      end

      -- Use cached status field or fetch it
      if cache.status_field then
        with_status_field(cache.status_field)
      else
        local owner = proj.owner
        local number = proj.number
        if not owner or not number then
          utils.notify("Project owner or number not configured", vim.log.levels.ERROR)
          callback(nil)
          return
        end
        M.fetch_column_field(number, owner, field_name, function(field, err)
          if err or not field then
            utils.notify(err or "Failed to fetch project fields", vim.log.levels.ERROR)
            callback(nil)
            return
          end
          with_status_field(field)
        end)
      end
    end

    -- Detect column field or use cached
    if cache.column_field_name then
      with_column_field(cache.column_field_name)
    else
      M.detect_column_field(project_id, with_column_field)
    end
  end

  -- Use cached project ID or resolve it
  if cache.project_id then
    with_project_id(cache.project_id)
  else
    local owner = proj.owner
    local number = proj.number
    if not owner or not number then
      utils.notify("Project owner or number not configured", vim.log.levels.ERROR)
      callback(nil)
      return
    end
    M.resolve_project_id(number, owner, function(project_id, err)
      if err or not project_id then
        utils.notify(err or "Failed to resolve project ID", vim.log.levels.ERROR)
        callback(nil)
        return
      end
      with_project_id(project_id)
    end)
  end
end

-- ---------------------------------------------------------------------------
-- Write operations
-- ---------------------------------------------------------------------------

--- Move an item to a different Status option.
---@param item_id string Project item node ID
---@param project_id string Project node ID
---@param field_id string Status field ID
---@param option_id string Target status option ID
---@param callback fun(ok: boolean, err: string|nil)
function M.move_item(item_id, project_id, field_id, option_id, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "project",
    "item-edit",
    "--id",
    item_id,
    "--project-id",
    project_id,
    "--field-id",
    field_id,
    "--single-select-option-id",
    option_id,
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(true, nil)
      else
        callback(false, result.stderr or "Failed to move project item")
      end
    end)
  end)
end

--- Add an issue to the project.
---@param issue_url string Full issue URL (e.g. "https://github.com/owner/repo/issues/42")
---@param project_number integer
---@param owner string
---@param callback fun(item_id: string|nil, err: string|nil)
function M.add_item(issue_url, project_number, owner, callback)
  local cmd = vim.list_extend(vim.deepcopy(gh_base_cmd()), {
    "project",
    "item-add",
    tostring(project_number),
    "--owner",
    owner,
    "--url",
    issue_url,
    "--format",
    "json",
  })
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, result.stderr or "Failed to add item to project")
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout)
      if ok and data and data.id then
        callback(data.id, nil)
      else
        callback(nil, nil) -- added but couldn't parse item ID
      end
    end)
  end)
end

--- Expand a column by revealing full issues from cache (no network request).
---@param col_index integer Column index in board_data.columns (1-based)
---@param callback fun(ok: boolean, err: string|nil)
function M.expand_column(col_index, callback)
  if not cache.board_data or not cache.board_data.columns[col_index] then
    callback(false, "Column not found")
    return
  end
  local col_data = cache.board_data.columns[col_index]
  if col_data.expanded then
    callback(true, nil)
    return
  end

  local full = cache.full_buckets and cache.full_buckets[col_data.label]
  if not full then
    callback(false, "No cached data")
    return
  end

  local cfg = require("okuban.config").get()
  local done_limit = cfg.project.done_limit or 20
  local display = full
  if #full > done_limit then
    display = {}
    for i = 1, done_limit do
      display[i] = full[i]
    end
  end

  col_data.issues = display
  col_data.has_more = #full > done_limit
  col_data.expanded = true
  cache.board_data_ts = os.time()
  callback(true, nil)
end

-- ---------------------------------------------------------------------------
-- Cache accessors
-- ---------------------------------------------------------------------------

--- Get the cached item node ID for an issue number.
---@param issue_number integer
---@return string|nil
function M.get_item_id(issue_number)
  return cache.item_map[issue_number]
end

--- Get the cached status field.
---@return table|nil { id, options = [...] }
function M.get_cached_status_field()
  return cache.status_field
end

--- Get the cached project node ID.
---@return string|nil
function M.get_cached_project_id()
  return cache.project_id
end

--- Get the cached column field name.
---@return string|nil
function M.get_cached_column_field_name()
  return cache.column_field_name
end

--- Return cached board data if it exists and is younger than max_age seconds.
---@param max_age integer Maximum cache age in seconds
---@return table|nil board_data
function M.get_cached_board_data(max_age)
  if cache.board_data and (os.time() - cache.board_data_ts) < max_age then
    return cache.board_data
  end
  return nil
end

--- Reset all caches (for testing and source switching).
function M.reset_cache()
  cache.project_id = nil
  cache.column_field_name = nil
  cache.status_field = nil
  cache.item_map = {}
  cache.board_data = nil
  cache.board_data_ts = 0
  cache.full_buckets = nil
end

--- Set cache values directly (for testing).
---@param project_id string|nil
---@param status_field table|nil
---@param column_field_name string|nil
function M._set_cache(project_id, status_field, column_field_name)
  cache.project_id = project_id
  cache.status_field = status_field
  cache.column_field_name = column_field_name
end

return M

local config = require("okuban.config")
local utils = require("okuban.utils")

local M = {}

--- Default patterns for classifying issues based on existing labels.
--- Keys are Lua patterns (case-insensitive match against label names).
--- Values are the target okuban column label.
---@type table<string, string>
M._DEFAULT_PATTERN_MAP = {
  -- status:* and kanban:* prefixes (common conventions)
  ["^status[:%-%s_]+backlog$"] = "okuban:backlog",
  ["^status[:%-%s_]+to%s*do$"] = "okuban:todo",
  ["^status[:%-%s_]+in%s*[-%s_]*progress$"] = "okuban:in-progress",
  ["^status[:%-%s_]+review$"] = "okuban:review",
  ["^status[:%-%s_]+done$"] = "okuban:done",
  ["^status[:%-%s_]+completed?$"] = "okuban:done",
  ["^kanban[:%-%s_]+backlog$"] = "okuban:backlog",
  ["^kanban[:%-%s_]+to%s*do$"] = "okuban:todo",
  ["^kanban[:%-%s_]+in%s*[-%s_]*progress$"] = "okuban:in-progress",
  ["^kanban[:%-%s_]+review$"] = "okuban:review",
  ["^kanban[:%-%s_]+done$"] = "okuban:done",
  ["^kanban[:%-%s_]+completed?$"] = "okuban:done",
  -- Bare keywords (exact match, case-insensitive)
  ["^backlog$"] = "okuban:backlog",
  ["^to%s*do$"] = "okuban:todo",
  ["^in%s*[-%s_]*progress$"] = "okuban:in-progress",
  ["^wip$"] = "okuban:in-progress",
  ["^review$"] = "okuban:review",
  ["^in%s*[-%s_]*review$"] = "okuban:review",
  ["^done$"] = "okuban:done",
  ["^completed?$"] = "okuban:done",
  ["^closed$"] = "okuban:done",
}

--- Classify a single issue into an okuban column label.
---@param issue table Issue with { number, title, labels, state }
---@param pattern_map table<string, string>
---@return string label, string reason
function M._classify_issue(issue, pattern_map)
  if issue.state == "CLOSED" or issue.state == "closed" then
    return "okuban:done", "closed"
  end
  if issue.labels then
    for _, lbl in ipairs(issue.labels) do
      local name = (lbl.name or ""):lower()
      for pattern, target in pairs(pattern_map) do
        if name:match(pattern) then
          return target, "label: " .. lbl.name
        end
      end
    end
  end
  return "okuban:backlog", "default"
end

--- Fetch all issues and build a triage plan.
---@param callback fun(plan: table|nil) nil if nothing to triage
function M.build_plan(callback)
  local cfg = config.get()
  local stop = utils.spinner_start("Scanning issues for triage...")

  local column_labels = {}
  for _, col in ipairs(cfg.columns) do
    column_labels[col.label] = true
  end

  local gh_cmd = vim.list_extend(vim.deepcopy(require("okuban.api")._gh_base_cmd()), {
    "issue",
    "list",
    "--json",
    "number,title,body,assignees,labels,state",
    "--limit",
    "500",
    "--state",
    cfg.triage.include_closed and "all" or "open",
  })

  vim.system(gh_cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        stop("Failed to fetch issues: " .. (result.stderr or ""))
        callback(nil)
        return
      end

      local ok, all_issues = pcall(vim.json.decode, result.stdout)
      if not ok or type(all_issues) ~= "table" then
        stop("Failed to parse issues")
        callback(nil)
        return
      end

      -- Filter: keep only issues without any okuban: label
      local candidates = {}
      for _, issue in ipairs(all_issues) do
        local has_okuban = false
        if issue.labels then
          for _, lbl in ipairs(issue.labels) do
            if column_labels[lbl.name] then
              has_okuban = true
              break
            end
          end
        end
        if not has_okuban then
          table.insert(candidates, issue)
        end
      end

      if #candidates == 0 then
        stop("No issues need triage")
        callback(nil)
        return
      end

      local entries = {}
      local summary = { done = 0, matched = 0, backlog = 0 }
      local ai_candidates = {}

      for _, issue in ipairs(candidates) do
        local target, reason = M._classify_issue(issue, M._DEFAULT_PATTERN_MAP)
        table.insert(entries, {
          number = issue.number,
          title = issue.title or "Untitled",
          target_label = target,
          reason = reason,
          state = issue.state,
        })
        if reason == "closed" then
          summary.done = summary.done + 1
        elseif reason == "default" then
          summary.backlog = summary.backlog + 1
          table.insert(ai_candidates, issue)
        else
          summary.matched = summary.matched + 1
        end
      end

      table.sort(entries, function(a, b)
        return a.number < b.number
      end)

      stop()
      callback({ entries = entries, summary = summary, ai_candidates = ai_candidates })
    end)
  end)
end

--- Show a confirmation floating window with triage summary.
---@param plan table Plan from build_plan
---@param callback fun(action: "apply"|"ai"|"skip")
function M.show_confirmation(plan, callback)
  local entries = plan.entries
  local summary = plan.summary

  local lines = { "", "  Total issues to label:  " .. #entries, "" }
  if summary.done > 0 then
    table.insert(lines, string.format("  okuban:done          %d  (closed issues)", summary.done))
  end
  if summary.matched > 0 then
    table.insert(lines, string.format("  pattern-matched      %d  (existing labels)", summary.matched))
  end
  if summary.backlog > 0 then
    table.insert(lines, string.format("  okuban:backlog       %d  (default for open issues)", summary.backlog))
  end

  table.insert(lines, "")
  table.insert(lines, "  Examples:")
  local shown = math.min(5, #entries)
  for i = 1, shown do
    local e = entries[i]
    local col_name = e.target_label:gsub("^okuban:", "")
    local title = #e.title > 40 and e.title:sub(1, 37) .. "..." or e.title
    table.insert(lines, string.format("    #%-5d %-12s %s", e.number, col_name, title))
  end
  if #entries > shown then
    table.insert(lines, "    ... and " .. (#entries - shown) .. " more")
  end
  table.insert(lines, "")

  -- AI option
  local ai_available = false
  if #plan.ai_candidates > 0 and config.get().triage.ai_enabled then
    local claude = require("okuban.claude")
    if claude.is_available() then
      ai_available = true
      table.insert(lines, string.format("  [a] AI triage %d backlog issue(s) with Claude", #plan.ai_candidates))
    end
  end
  table.insert(lines, "  [y] Apply labels    [n] Skip")
  table.insert(lines, "")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "okuban"

  local max_width = math.min(70, vim.o.columns - 6)
  local width = math.min(56, max_width)
  for _, line in ipairs(lines) do
    width = math.max(width, #line + 4)
  end
  width = math.min(width, max_width)

  local screen_w = vim.o.columns
  local screen_h = vim.o.lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((screen_h - #lines) / 2),
    col = math.floor((screen_w - width) / 2),
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " Triage Summary ",
    title_pos = "center",
    zindex = 70,
  })
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false

  local called = false
  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function safe_callback(action)
    if called then
      return
    end
    called = true
    close_win()
    callback(action)
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      safe_callback("skip")
    end,
  })

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "y", function()
    safe_callback("apply")
  end, opts)
  vim.keymap.set("n", "n", function()
    safe_callback("skip")
  end, opts)
  vim.keymap.set("n", "q", function()
    safe_callback("skip")
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    safe_callback("skip")
  end, opts)
  if ai_available then
    vim.keymap.set("n", "a", function()
      safe_callback("ai")
    end, opts)
  end
end

local BATCH_SIZE = 15

--- Apply triage plan by adding okuban labels to issues.
--- Additive only — never removes existing labels.
---@param plan table Plan from build_plan
---@param callback fun(applied: integer, failed: integer)
function M.apply_plan(plan, callback)
  local entries = plan.entries
  if #entries == 0 then
    callback(0, 0)
    return
  end

  local stop = utils.spinner_start(string.format("Applying labels... 0/%d", #entries))
  local gh_base = require("okuban.api")._gh_base_cmd()
  local applied = 0
  local failed = 0
  local idx = 0

  local function process_batch()
    local batch_start = idx + 1
    local batch_end = math.min(idx + BATCH_SIZE, #entries)
    if batch_start > #entries then
      local msg = failed > 0 and string.format("Triage: applied %d labels, %d failed", applied, failed)
        or string.format("Triage: applied %d labels", applied)
      stop(msg)
      callback(applied, failed)
      return
    end

    local batch_pending = batch_end - batch_start + 1
    for i = batch_start, batch_end do
      local entry = entries[i]
      local cmd = vim.list_extend(vim.deepcopy(gh_base), {
        "issue",
        "edit",
        tostring(entry.number),
        "--add-label",
        entry.target_label,
      })
      vim.system(cmd, { text = true }, function(result)
        vim.schedule(function()
          if result.code == 0 then
            applied = applied + 1
          else
            failed = failed + 1
          end
          batch_pending = batch_pending - 1
          utils.spinner_update(string.format("Applying labels... %d/%d", applied + failed, #entries))
          if batch_pending == 0 then
            idx = batch_end
            process_batch()
          end
        end)
      end)
    end
  end

  process_batch()
end

--- Run AI-assisted triage on backlog candidates via claude CLI.
---@param candidates table[] Issues assigned to backlog by default
---@param callback fun(suggestions: table[]|nil)
function M.run_ai_triage(candidates, callback)
  if #candidates == 0 then
    callback(nil)
    return
  end

  local claude = require("okuban.claude")
  if not claude.is_available() then
    utils.notify("Claude CLI not available", vim.log.levels.WARN)
    callback(nil)
    return
  end

  local stop = utils.spinner_start("AI triage: analyzing issues...")
  local cfg = config.get()
  local column_names = {}
  for _, col in ipairs(cfg.columns) do
    table.insert(column_names, col.label)
  end

  local issue_lines = {}
  for _, issue in ipairs(candidates) do
    local labels_str = ""
    if issue.labels then
      local names = {}
      for _, lbl in ipairs(issue.labels) do
        table.insert(names, lbl.name)
      end
      labels_str = table.concat(names, ", ")
    end
    table.insert(
      issue_lines,
      string.format("- #%d: %s [labels: %s]", issue.number, issue.title or "Untitled", labels_str)
    )
  end

  local prompt = string.format(
    [[Classify these GitHub issues into kanban columns. Available columns: %s

Issues:
%s

Respond ONLY with a JSON array. Each element: {"number": <int>, "label": "<column_label>"}
Do NOT use okuban:backlog — pick a more specific column if possible. If truly unclear, omit the issue.]],
    table.concat(column_names, ", "),
    table.concat(issue_lines, "\n")
  )

  vim.system({ "claude", "-p", prompt, "--output-format", "json" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        stop("AI triage failed: " .. (result.stderr or "unknown error"))
        callback(nil)
        return
      end

      -- Parse JSON — claude --output-format json wraps in {"result": "..."}
      local ok, outer = pcall(vim.json.decode, result.stdout)
      if not ok or type(outer) ~= "table" then
        stop("AI triage: could not parse response")
        callback(nil)
        return
      end

      local inner_str = outer.result or result.stdout
      local arr_ok, suggestions = pcall(vim.json.decode, inner_str)
      if not arr_ok or type(suggestions) ~= "table" then
        local arr_match = inner_str:match("%[.-%]")
        if arr_match then
          arr_ok, suggestions = pcall(vim.json.decode, arr_match)
        end
        if not arr_ok or type(suggestions) ~= "table" then
          stop("AI triage: invalid response format")
          callback(nil)
          return
        end
      end

      -- Validate: only keep entries with known column labels (not backlog)
      local valid_labels = {}
      for _, col in ipairs(cfg.columns) do
        valid_labels[col.label] = true
      end
      local valid = {}
      for _, s in ipairs(suggestions) do
        if type(s) == "table" and s.number and s.label and valid_labels[s.label] and s.label ~= "okuban:backlog" then
          table.insert(valid, s)
        end
      end

      if #valid == 0 then
        stop("AI triage: no actionable suggestions")
        callback(nil)
        return
      end
      stop(string.format("AI triage: %d suggestion(s)", #valid))
      callback(valid)
    end)
  end)
end

--- Apply AI triage suggestions by swapping backlog → suggested label.
---@param suggestions table[] Array of { number, label }
---@param callback fun(applied: integer, failed: integer)
function M._apply_ai_suggestions(suggestions, callback)
  if #suggestions == 0 then
    callback(0, 0)
    return
  end

  local stop = utils.spinner_start(string.format("AI triage: applying %d suggestion(s)...", #suggestions))
  local gh_base = require("okuban.api")._gh_base_cmd()
  local applied = 0
  local failed = 0
  local pending = #suggestions

  for _, s in ipairs(suggestions) do
    local cmd = vim.list_extend(vim.deepcopy(gh_base), {
      "issue",
      "edit",
      tostring(s.number),
      "--remove-label",
      "okuban:backlog",
      "--add-label",
      s.label,
    })
    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          applied = applied + 1
        else
          failed = failed + 1
        end
        pending = pending - 1
        if pending == 0 then
          local msg = failed > 0 and string.format("AI triage: applied %d, %d failed", applied, failed)
            or string.format("AI triage: applied %d suggestion(s)", applied)
          stop(msg)
          callback(applied, failed)
        end
      end)
    end)
  end
end

--- Run the full triage flow: build plan → confirm → apply → optional AI.
---@param callback fun()|nil Optional callback when complete
function M.run(callback)
  callback = callback or function() end

  M.build_plan(function(plan)
    if not plan then
      callback()
      return
    end

    M.show_confirmation(plan, function(action)
      if action == "skip" then
        utils.notify("Triage skipped")
        callback()
        return
      end

      M.apply_plan(plan, function(applied, _failed)
        if action == "ai" and #plan.ai_candidates > 0 then
          M.run_ai_triage(plan.ai_candidates, function(suggestions)
            if suggestions and #suggestions > 0 then
              M._apply_ai_suggestions(suggestions, function()
                callback()
              end)
            else
              callback()
            end
          end)
        else
          if applied > 0 then
            utils.notify("Triage complete — open :Okuban to see your board")
          end
          callback()
        end
      end)
    end)
  end)
end

--- Reset module state (for tests).
function M._reset() end

return M

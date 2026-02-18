local config = require("okuban.config")

local M = {}

-- U+2026 HORIZONTAL ELLIPSIS (3 bytes in UTF-8)
local ELLIPSIS = "\xe2\x80\xa6"

--- Word-wrap text into lines of at most `width` characters using greedy algorithm.
---@param text string
---@param width integer
---@return string[]
function M.wrap_text(text, width)
  if not text or text == "" then
    return { "" }
  end
  if width <= 0 then
    return { text }
  end

  local lines = {}
  local current = ""

  for word in text:gmatch("%S+") do
    if current == "" then
      -- First word on this line — always add even if it exceeds width
      current = word
    elseif #current + 1 + #word <= width then
      current = current .. " " .. word
    else
      table.insert(lines, current)
      current = word
    end
  end

  if current ~= "" then
    table.insert(lines, current)
  end

  if #lines == 0 then
    return { "" }
  end

  return lines
end

--- Strip conventional commit prefix from a title.
--- "feat(api): preflight checks" → "Preflight checks", "feat"
--- "fix: broken link" → "Broken link", "fix"
--- "plain title" → "Plain title", nil
---@param title string
---@return string clean_title
---@return string|nil type_tag
function M.strip_commit_prefix(title)
  if not title or title == "" then
    return "", nil
  end
  -- Match: type(scope): description  OR  type: description
  local type_tag, desc = title:match("^(%w+)%(.-%):%s*(.+)$")
  if not type_tag then
    type_tag, desc = title:match("^(%w+):%s*(.+)$")
  end
  if desc then
    desc = desc:sub(1, 1):upper() .. desc:sub(2)
    return desc, type_tag
  end
  return title, nil
end

--- Extract TLDR from issue body markdown.
--- Looks for ## Summary or ## Bug section, falls back to first paragraph.
---@param body string|nil
---@return string|nil
function M.extract_tldr(body)
  if not body or type(body) ~= "string" or body == "" then
    return nil
  end

  -- Find a summary section: ## Summary or ## Bug
  local section_start = body:find("## [Ss]ummary%s*\n") or body:find("## [Bb]ug%s*\n")

  if section_start then
    local content_start = body:find("\n", section_start)
    if content_start then
      content_start = content_start + 1
      local section_end = body:find("\n##", content_start) or #body + 1
      local section_text = body:sub(content_start, section_end - 1)
      -- Join lines, collapse whitespace, strip markdown formatting
      local text = section_text:gsub("\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
      text = text:gsub("`", ""):gsub("%*%*", "")
      if text ~= "" then
        return text
      end
    end
  end

  -- Fallback: first non-empty, non-heading line
  for line in body:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^#") then
      trimmed = trimmed:gsub("`", ""):gsub("%*%*", "")
      return trimmed
    end
  end

  return nil
end

--- Format compact metadata string: "feat · @alice" or "bug" or "@alice"
---@param issue table
---@param type_tag string|nil Type extracted from title prefix
---@return string|nil
function M.format_compact_metadata(issue, type_tag)
  local parts = {}

  -- Type: prefer tag from title prefix, fall back to type: label
  if type_tag then
    table.insert(parts, type_tag)
  elseif issue.labels then
    for _, lbl in ipairs(issue.labels) do
      local type_name = lbl.name:match("^type:%s*(.+)")
      if type_name then
        table.insert(parts, type_name)
        break
      end
    end
  end

  -- Assignee
  if issue.assignees and #issue.assignees > 0 then
    table.insert(parts, "@" .. issue.assignees[1].login)
  end

  if #parts == 0 then
    return nil
  end

  return table.concat(parts, " \xc2\xb7 ") -- U+00B7 MIDDLE DOT
end

--- Render a single issue as a compact one-line card.
--- If the issue has a linked worktree (worktree_map provided), shows [WT] badge.
--- If the issue has an active Claude session, shows status badge.
---@param issue table { number, title }
---@param width integer Available width for text
---@param worktree_map table<integer, table>|nil Map of issue number → worktree info
---@param claude_sessions table<integer, table>|nil Map of issue number → session info
---@param sub_issue_counts table<integer, {total: integer, completed: integer}>|nil
---@return string
function M.render_card(issue, width, worktree_map, claude_sessions, sub_issue_counts)
  local title = M.strip_commit_prefix(issue.title or "")
  local prefix = " #" .. issue.number .. " "

  -- Sub-issue count badge (after title, before worktree/session badges)
  local sub_badge = ""
  local sub_info = (sub_issue_counts and sub_issue_counts[issue.number]) or issue.sub_issue_counts
  if sub_info and sub_info.total and sub_info.total > 0 then
    sub_badge = " (" .. sub_info.total .. ")"
  end

  -- Check for worktree badge (active worktrees use highlight color instead of badge)
  local badge = ""
  if worktree_map and worktree_map[issue.number] then
    local wt = worktree_map[issue.number]
    if wt.active then
      -- No badge — active worktrees are indicated via OkubanCardActive highlight
      badge = ""
    elseif wt.dirty then
      badge = " [\xe2\x97\x8f]" -- U+25CF BLACK CIRCLE (dirty)
    else
      badge = " [\xe2\x97\x8b]" -- U+25CB WHITE CIRCLE (clean)
    end
  end

  -- Session status badge
  if claude_sessions and claude_sessions[issue.number] then
    local s = claude_sessions[issue.number]
    if s.status == "running" then
      badge = badge .. " [\xe2\x96\xb6]" -- U+25B6 BLACK RIGHT-POINTING TRIANGLE
    elseif s.status == "completed" then
      badge = badge .. " [\xe2\x9c\x93]" -- U+2713 CHECK MARK
    elseif s.status == "failed" then
      badge = badge .. " [\xe2\x9c\x97]" -- U+2717 BALLOT X
    end
  end

  local avail = width - #prefix - #sub_badge - #badge
  if avail < 1 then
    return prefix .. sub_badge .. badge
  end
  if #title > avail then
    title = title:sub(1, avail - 1) .. ELLIPSIS
  end
  return prefix .. title .. sub_badge .. badge
end

--- Render all cards for a column as a compact list (one line per card).
---@param issues table[] List of issues
---@param width integer Available width for text
---@param worktree_map table<integer, table>|nil Map of issue number → worktree info
---@param claude_sessions table<integer, table>|nil Map of issue number → session info
---@param sub_issue_counts table<integer, {total: integer, completed: integer}>|nil
---@return string[] lines
---@return table[] card_ranges Array of { start_line: integer, end_line: integer } (1-indexed)
function M.render_column(issues, width, worktree_map, claude_sessions, sub_issue_counts)
  if #issues == 0 then
    return { "  (no issues)" }, {}
  end

  local lines = {}
  local card_ranges = {}
  for i, issue in ipairs(issues) do
    table.insert(lines, M.render_card(issue, width, worktree_map, claude_sessions, sub_issue_counts))
    table.insert(card_ranges, { start_line = i, end_line = i })
  end
  return lines, card_ranges
end

--- Render preview pane content for the selected issue.
--- Shows full title (word-wrapped), TLDR from body, metadata, worktree status, and session info.
---@param issue table|nil { number, title, body, assignees, labels }
---@param width integer Available width
---@param height integer Number of lines in preview pane
---@param worktree_map table<integer, table>|nil Map of issue number → worktree info
---@param claude_sessions table<integer, table>|nil Map of issue number → session info
---@param sub_issue_counts table<integer, {total: integer, completed: integer}>|nil
---@return string[]
function M.render_preview(issue, width, height, worktree_map, claude_sessions, sub_issue_counts)
  if not issue then
    local lines = {}
    for _ = 1, height do
      table.insert(lines, "")
    end
    return lines
  end

  local cfg = config.get()
  local lines = {}
  local title, type_tag = M.strip_commit_prefix(issue.title or "")

  -- Full title (word-wrapped)
  local title_prefix = "#" .. issue.number .. " "
  local title_width = width - #title_prefix
  if title_width < 1 then
    title_width = 1
  end
  local wrapped = M.wrap_text(title, title_width)
  local indent = string.rep(" ", #title_prefix)
  for i, line in ipairs(wrapped) do
    if #lines >= height then
      break
    end
    if i == 1 then
      table.insert(lines, title_prefix .. line)
    else
      table.insert(lines, indent .. line)
    end
  end

  -- TLDR from body
  if cfg.show_tldr and issue.body then
    local tldr = M.extract_tldr(issue.body)
    if tldr and tldr ~= "" then
      if #lines < height then
        table.insert(lines, "")
      end
      local tldr_wrapped = M.wrap_text(tldr, width)
      for _, line in ipairs(tldr_wrapped) do
        if #lines >= height then
          break
        end
        table.insert(lines, line)
      end
    end
  end

  -- Metadata
  local meta = M.format_compact_metadata(issue, type_tag)
  if meta and #lines < height - 1 then
    table.insert(lines, "")
    table.insert(lines, meta)
  end

  -- Worktree status (active is indicated by orange highlight in column, not here)
  if worktree_map and worktree_map[issue.number] and #lines < height - 1 then
    local wt = worktree_map[issue.number]
    local parts = {}
    if wt.dirty then
      table.insert(parts, "\xe2\x97\x8f dirty") -- U+25CF
    else
      table.insert(parts, "\xe2\x97\x8b clean") -- U+25CB
    end
    if wt.branch then
      table.insert(parts, wt.branch)
    end
    table.insert(lines, "")
    table.insert(lines, table.concat(parts, " \xc2\xb7 "))
  end

  -- Sub-issue progress
  local sub_info = (sub_issue_counts and sub_issue_counts[issue.number]) or issue.sub_issue_counts
  if sub_info and sub_info.total and sub_info.total > 0 and #lines < height - 1 then
    table.insert(lines, "")
    table.insert(lines, string.format("%d/%d sub-issues", sub_info.completed, sub_info.total))
  end

  -- Claude session status
  if claude_sessions and issue and claude_sessions[issue.number] and #lines < height - 1 then
    local s = claude_sessions[issue.number]
    local session_parts = {}
    if s.status == "running" then
      table.insert(session_parts, "\xe2\x96\xb6 Claude running") -- U+25B6
    elseif s.status == "completed" then
      table.insert(session_parts, "\xe2\x9c\x93 Claude completed") -- U+2713
    elseif s.status == "failed" then
      table.insert(session_parts, "\xe2\x9c\x97 Claude failed") -- U+2717
    end
    if s.cost_usd then
      table.insert(session_parts, string.format("$%.2f", s.cost_usd))
    end
    if s.num_turns then
      table.insert(session_parts, s.num_turns .. " turns")
    end
    if #session_parts > 0 then
      table.insert(lines, "")
      table.insert(lines, table.concat(session_parts, " \xc2\xb7 "))
    end
  end

  -- Pad to height
  while #lines < height do
    table.insert(lines, "")
  end

  return lines
end

return M

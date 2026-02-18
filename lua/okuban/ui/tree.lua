--- Sub-issue tree expansion state and rendering.
--- Manages expanded/collapsed state per column/parent, caches sub-issues,
--- and builds the flat visible-item list for column rendering.
local M = {}

-- U+2026 HORIZONTAL ELLIPSIS (3 bytes in UTF-8)
local ELLIPSIS = "\xe2\x80\xa6"

--- Expansion state: expanded[col_idx][parent_number] = sub_issues[] | true (loading).
---@type table<integer, table<integer, table[]|true>>
local expanded = {}

--- Session-scoped sub-issue cache (survives reset/refresh).
---@type table<integer, table[]>
local sub_cache = {}

-- ---------------------------------------------------------------------------
-- State management
-- ---------------------------------------------------------------------------

--- Reset expansion state (NOT cache). Call on board close/refresh.
function M.reset()
  expanded = {}
end

--- Check if a parent issue is expanded in a column.
---@param col_idx integer
---@param parent_number integer
---@return boolean
function M.is_expanded(col_idx, parent_number)
  return expanded[col_idx] ~= nil and expanded[col_idx][parent_number] ~= nil
end

--- Check if a parent issue is in the loading state.
---@param col_idx integer
---@param parent_number integer
---@return boolean
function M.is_loading(col_idx, parent_number)
  return expanded[col_idx] ~= nil and expanded[col_idx][parent_number] == true
end

--- Store sub-issues for an expanded parent and update cache.
---@param col_idx integer
---@param parent_number integer
---@param subs table[] Array of { number, title, state, body }
function M.set_expanded(col_idx, parent_number, subs)
  if not expanded[col_idx] then
    expanded[col_idx] = {}
  end
  expanded[col_idx][parent_number] = subs
  sub_cache[parent_number] = subs
end

--- Mark a parent as loading (sentinel value `true`).
---@param col_idx integer
---@param parent_number integer
function M.set_loading(col_idx, parent_number)
  if not expanded[col_idx] then
    expanded[col_idx] = {}
  end
  expanded[col_idx][parent_number] = true
end

--- Collapse a single parent in a column.
---@param col_idx integer
---@param parent_number integer
function M.collapse(col_idx, parent_number)
  if expanded[col_idx] then
    expanded[col_idx][parent_number] = nil
  end
end

--- Collapse all expansions in a column.
---@param col_idx integer
function M.collapse_all(col_idx)
  expanded[col_idx] = nil
end

--- Check if any parent is expanded in a column.
---@param col_idx integer
---@return boolean
function M.has_any_expanded(col_idx)
  return expanded[col_idx] ~= nil and next(expanded[col_idx]) ~= nil
end

--- Get cached sub-issues for a parent (session-scoped).
---@param parent_number integer
---@return table[]|nil
function M.get_cached(parent_number)
  return sub_cache[parent_number]
end

-- ---------------------------------------------------------------------------
-- Visible item list
-- ---------------------------------------------------------------------------

--- Build a flat list of visible items for a column, interleaving cards and
--- expanded sub-issues.
---@param col table Column with .issues array
---@param col_idx integer
---@return table[] items Array of { type = "card"|"sub_issue"|"loading", ... }
function M.build_visible_items(col, col_idx)
  local items = {}
  for card_idx, issue in ipairs(col.issues) do
    table.insert(items, { type = "card", issue = issue, card_idx = card_idx })

    local exp = expanded[col_idx] and expanded[col_idx][issue.number]
    if exp == true then
      -- Loading placeholder
      table.insert(items, { type = "loading", parent_idx = card_idx })
    elseif type(exp) == "table" then
      for pos, sub in ipairs(exp) do
        table.insert(items, {
          type = "sub_issue",
          sub = sub,
          parent_idx = card_idx,
          position = pos,
          is_last = (pos == #exp),
        })
      end
    end
  end
  return items
end

-- ---------------------------------------------------------------------------
-- Rendering helpers
-- ---------------------------------------------------------------------------

--- Render a single sub-issue line with tree characters.
--- Format: " {tree_char} {state_icon} #{number} {title}"
---@param sub table { number, title, state }
---@param is_last boolean Whether this is the last sub-issue
---@param width integer Available width
---@return string
function M.render_sub_issue_line(sub, is_last, width)
  local tree_char = is_last and "\xe2\x94\x94" or "\xe2\x94\x9c" -- U+2514 / U+251C
  local state_icon
  if sub.state == "CLOSED" or sub.state == "closed" then
    state_icon = "\xe2\x9c\x93" -- U+2713 CHECK MARK
  else
    state_icon = "\xe2\x97\x8b" -- U+25CB WHITE CIRCLE (open)
  end

  local num_str = tostring(sub.number)
  local prefix = " " .. tree_char .. " " .. state_icon .. " #" .. num_str .. " "
  local title = sub.title or ""

  -- Compute display width: tree_char and state_icon are each 1 cell, rest is ASCII
  -- " ├ ○ #NNN " → space(1) + tree(1) + space(1) + icon(1) + space(1) + #(1) + num + space(1)
  local prefix_display = 7 + #num_str
  local avail = width - prefix_display
  if avail < 1 then
    return prefix
  end
  if #title > avail then
    title = title:sub(1, avail - 1) .. ELLIPSIS
  end
  return prefix .. title
end

--- Render a loading placeholder line.
---@param width integer Available width
---@return string
function M.render_loading_line(width)
  local line = " \xe2\x94\x94 loading..." -- U+2514
  if #line > width then
    return line:sub(1, width)
  end
  return line
end

return M

local M = {}

--- Format a single issue as a card line.
---@param issue table { number, title, assignees }
---@param width integer Available width for text
---@return string
function M.render_card(issue, width)
  local prefix = "#" .. issue.number .. " "
  local available = width - #prefix
  local title = issue.title or ""
  if #title > available then
    title = title:sub(1, available - 3) .. "..."
  end
  return prefix .. title
end

--- Render all cards for a column.
---@param issues table[] List of issues
---@param width integer Available width for text
---@return string[] lines
function M.render_column(issues, width)
  if #issues == 0 then
    return { "  (no issues)" }
  end
  local lines = {}
  for _, issue in ipairs(issues) do
    table.insert(lines, M.render_card(issue, width))
  end
  return lines
end

return M

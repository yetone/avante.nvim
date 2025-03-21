---@alias avante.ui.LineSection string[]
---
---@class avante.ui.Line
---@field sections avante.ui.LineSection[]
local M = {}
M.__index = M

---@param sections avante.ui.LineSection[]
function M:new(sections)
  local this = setmetatable({}, M)
  this.sections = sections
  return this
end

---@param ns_id number
---@param bufnr number
---@param line number
function M:set_highlights(ns_id, bufnr, line)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local col_start = 0
  for _, section in ipairs(self.sections) do
    local text = section[1]
    local highlight = section[2]
    if highlight then vim.api.nvim_buf_add_highlight(bufnr, ns_id, highlight, line, col_start, col_start + #text) end
    col_start = col_start + #text
  end
end

function M:__tostring()
  local content = {}
  for _, section in ipairs(self.sections) do
    local text = section[1]
    table.insert(content, text)
  end
  return table.concat(content, "")
end

return M

---@class avante.SelectionResult
---@field content string Selected content
---@field range avante.Range Selection range
local SelectionResult = {}
SelectionResult.__index = SelectionResult

-- Create a selection content and range
---@param content string Selected content
---@param range avante.Range Selection range
function SelectionResult.new(content, range)
  local self = setmetatable({}, SelectionResult)
  self.content = content
  self.range = range
  return self
end

return SelectionResult

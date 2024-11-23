---@class avante.Range
---@field start avante.RangeSelection start point
---@field finish avante.RangeSelection Selection end point
local Range = {}
Range.__index = Range

---@class avante.RangeSelection: table<string, integer>
---@field line number
---@field col number

---Create a selection range
---@param start avante.RangeSelection Selection start point
---@param finish avante.RangeSelection Selection end point
function Range:new(start, finish)
  local instance = setmetatable({}, Range)
  instance.start = start
  instance.finish = finish
  return instance
end

return Range

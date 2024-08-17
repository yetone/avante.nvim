--@class avante.Range
--@field start table Selection start point
--@field start.line number Line number of the selection start
--@field start.col number Column number of the selection start
--@field finish table Selection end point
--@field finish.line number Line number of the selection end
--@field finish.col number Column number of the selection end
local Range = {}
Range.__index = Range
-- Create a selection range
-- @param start table Selection start point
-- @param start.line number Line number of the selection start
-- @param start.col number Column number of the selection start
-- @param finish table Selection end point
-- @param finish.line number Line number of the selection end
-- @param finish.col number Column number of the selection end
function Range.new(start, finish)
  local self = setmetatable({}, Range)
  self.start = start
  self.finish = finish
  return self
end

return Range

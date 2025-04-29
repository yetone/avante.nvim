local Utils = require("avante.utils")

---@class avante.HistoryMessage
local M = {}
M.__index = M

---@param message AvanteLLMMessage
---@param opts? {is_user_submission?: boolean, visible?: boolean, displayed_content?: string, state?: avante.HistoryMessageState, uuid?: string, selected_filepaths?: string[], selected_code?: AvanteSelectedCode, just_for_display?: boolean}
---@return avante.HistoryMessage
function M:new(message, opts)
  opts = opts or {}
  local obj = setmetatable({}, M)
  obj.message = message
  obj.uuid = opts.uuid or Utils.uuid()
  obj.state = opts.state or "generated"
  obj.timestamp = Utils.get_timestamp()
  obj.is_user_submission = false
  obj.visible = true
  if opts.is_user_submission ~= nil then obj.is_user_submission = opts.is_user_submission end
  if opts.visible ~= nil then obj.visible = opts.visible end
  if opts.displayed_content ~= nil then obj.displayed_content = opts.displayed_content end
  if opts.selected_filepaths ~= nil then obj.selected_filepaths = opts.selected_filepaths end
  if opts.selected_code ~= nil then obj.selected_code = opts.selected_code end
  if opts.just_for_display ~= nil then obj.just_for_display = opts.just_for_display end
  return obj
end

return M

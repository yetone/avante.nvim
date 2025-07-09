local Utils = require("avante.utils")

local M = {}

---If message is a "tool use" message returns information about the tool invocation.
---@param message avante.HistoryMessage
---@return AvanteLLMToolUse | nil
function M.get_tool_use_data(message)
  local content = message.message.content
  if type(content) == "table" then
    assert(#content == 1, "more than one entry in message content")
    local item = content[1]
    if item.type == "tool_use" then
      ---@cast item AvanteLLMToolUse
      return item
    end
  end
end

---@param message avante.HistoryMessage
---@return boolean
function M.is_tool_use_message(message) return M.get_tool_use_data(message) ~= nil end

---If message is a "tool result" message returns results of the tool invocation.
---@param message avante.HistoryMessage
---@return AvanteLLMToolResult | nil
function M.get_tool_result_data(message)
  local content = message.message.content
  if type(content) == "table" then
    assert(#content == 1, "more than one entry in message content")
    local item = content[1]
    if item.type == "tool_result" then
      ---@cast item AvanteLLMToolResult
      return item
    end
  end
end

---Attempts to locate result of a tool execution given tool invocation ID
---@param id string
---@param messages avante.HistoryMessage[]
---@return AvanteLLMToolResult | nil
function M.get_tool_result(id, messages)
  for idx = #messages, 1, -1 do
    local msg = messages[idx]
    local result = M.get_tool_result_data(msg)
    if result and result.tool_use_id == id then return result end
  end
end

---@param message avante.HistoryMessage
---@return boolean
function M.is_tool_result_message(message) return M.get_tool_result_data(message) ~= nil end

---Given a tool result message locate corresponding tool use message
---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@return avante.HistoryMessage | nil
function M.get_tool_use_message(message, messages)
  local result = M.get_tool_result_data(message)
  if result then
    for idx = #messages, 1, -1 do
      local msg = messages[idx]
      local use = M.get_tool_use_data(msg)
      if use and use.id == result.tool_use_id then return msg end
    end
  end
end

---Given a tool use message locate corresponding tool result message
---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@return avante.HistoryMessage | nil
function M.get_tool_result_message(message, messages)
  local use = M.get_tool_use_data(message)
  if use then
    for idx = #messages, 1, -1 do
      local msg = messages[idx]
      local result = M.get_tool_result_data(msg)
      if result and result.tool_use_id == use.id then return msg end
    end
  end
end

return M

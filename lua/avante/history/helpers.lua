local Utils = require("avante.utils")

local M = {}

---@param message avante.HistoryMessage
---@return boolean
function M.is_tool_use_message(message)
  local content = message.message.content
  if type(content) == "string" then return false end
  if vim.islist(content) then
    for _, item in ipairs(content) do
      if item.type == "tool_use" then return true end
    end
  end
  return false
end

---@param message avante.HistoryMessage
---@return boolean
function M.is_tool_result_message(message)
  local content = message.message.content
  if type(content) == "string" then return false end
  if vim.islist(content) then
    for _, item in ipairs(content) do
      if item.type == "tool_result" then return true end
    end
  end
  return false
end

---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@return avante.HistoryMessage | nil
function M.get_tool_use_message(message, messages)
  local content = message.message.content
  if type(content) == "string" then return nil end
  if vim.islist(content) then
    local tool_id = nil
    for _, item in ipairs(content) do
      if item.type == "tool_result" then
        tool_id = item.tool_use_id
        break
      end
    end
    if not tool_id then return nil end
    for idx_ = #messages, 1, -1 do
      local message_ = messages[idx_]
      local content_ = message_.message.content
      if type(content_) == "table" then
        for _, item in ipairs(content_) do
          if item.type == "tool_use" and item.id == tool_id then return message_ end
        end
      end
    end
  end
  return nil
end

---@param tool_use_message avante.HistoryMessage | nil
function M.is_edit_func_call_message(tool_use_message)
  local is_replace_func_call = false
  local is_str_replace_editor_func_call = false
  local is_str_replace_based_edit_tool_func_call = false
  local path = nil
  if tool_use_message and M.is_tool_use_message(tool_use_message) then
    local tool_use = tool_use_message.message.content[1]
    ---@cast tool_use AvanteLLMToolUse
    return Utils.is_edit_func_call_tool_use(tool_use)
  end
  return is_replace_func_call, is_str_replace_editor_func_call, is_str_replace_based_edit_tool_func_call, path
end

---@param message avante.HistoryMessage
---@param messages avante.HistoryMessage[]
---@return avante.HistoryMessage | nil
function M.get_tool_result_message(message, messages)
  local content = message.message.content
  if type(content) == "string" then return nil end
  if vim.islist(content) then
    local tool_id = nil
    for _, item in ipairs(content) do
      if item.type == "tool_use" then
        tool_id = item.id
        break
      end
    end
    if not tool_id then return nil end
    for idx_ = #messages, 1, -1 do
      local message_ = messages[idx_]
      local content_ = message_.message.content
      if type(content_) == "table" then
        for _, item in ipairs(content_) do
          if item.type == "tool_result" and item.tool_use_id == tool_id then return message_ end
        end
      end
    end
  end
  return nil
end

return M

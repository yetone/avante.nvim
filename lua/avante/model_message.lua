local Utils = require("avante.utils")

---@class avante.ModelMessage
local M = {}
M.__index = M

---@class avante.ModelMessage.Opts
---@field uuid? string
---@field turn_id? string
---@field state? avante.HistoryMessageState
---@field original_content? AvanteLLMMessageContent
---@field selected_code? AvanteSelectedCode
---@field selected_filepaths? string[]
---@field is_user_submission? boolean
---@field is_context? boolean
---@field is_compacted? boolean
---@field is_deleted? boolean
---@field provider? string
---@field model? string
---@field tool_use_logs? string[]
---@field tool_use_store? table
---

---Create a new ModelMessage instance
---@param role "user" | "assistant"
---@param content AvanteLLMMessageContentItem
---@param opts? avante.ModelMessage.Opts
---@return avante.ModelMessage
function M:new(role, content, opts)
  ---@type AvanteLLMMessage
  local message = { role = role, content = type(content) == "string" and content or { content } }
  local obj = {
    message = message,
    uuid = Utils.uuid(),
    state = "generated",
    timestamp = Utils.get_timestamp(),
    is_user_submission = false,
    is_context = false,
    is_compacted = false,
    is_deleted = false,
  }
  obj = vim.tbl_extend("force", obj, opts or {})
  return setmetatable(obj, M)
end

---Creates a new instance of synthetic ModelMessage
---@param role "assistant" | "user"
---@param item AvanteLLMMessageContentItem
---@return avante.ModelMessage
function M:new_synthetic(role, item)
  return M:new(role, item, { is_dummy = true })
end

---Creates a new instance of synthetic ModelMessage attributed to the assistant
---@param item AvanteLLMMessageContentItem
---@return avante.ModelMessage
function M:new_assistant_synthetic(item)
  return M:new_synthetic("assistant", item)
end

---Creates a new instance of synthetic ModelMessage attributed to the user
---@param item AvanteLLMMessageContentItem
---@return avante.ModelMessage
function M:new_user_synthetic(item)
  return M:new_synthetic("user", item)
end

---Updates content of a message as long as it is a simple text (or empty).
---@param new_content string
function M:update_content(new_content)
  assert(type(self.message.content) == "string", "can only update content of simple string messages")
  self.message.content = new_content
end

---Check if this ModelMessage is a tool use
---@return boolean
function M:is_tool_use()
  if type(self.message.content) == "table" then
    for _, item in ipairs(self.message.content) do
      if type(item) == "table" and item.type == "tool_use" then
        return true
      end
    end
  end
  return false
end

---Check if this ModelMessage is a tool result
---@return boolean
function M:is_tool_result()
  if type(self.message.content) == "table" then
    for _, item in ipairs(self.message.content) do
      if type(item) == "table" and item.type == "tool_result" then
        return true
      end
    end
  end
  return false
end

---Get tool use data from this ModelMessage
---@return AvanteLLMToolUse | nil
function M:get_tool_use()
  if type(self.message.content) == "table" then
    for _, item in ipairs(self.message.content) do
      if type(item) == "table" and item.type == "tool_use" then
        return {
          name = item.name,
          id = item.id,
          input = item.input,
        }
      end
    end
  end
  return nil
end

---Get tool result data from this ModelMessage
---@return AvanteLLMToolResult | nil
function M:get_tool_result()
  if type(self.message.content) == "table" then
    for _, item in ipairs(self.message.content) do
      if type(item) == "table" and item.type == "tool_result" then
        return {
          tool_name = "", -- Tool name is not stored in tool_result
          tool_use_id = item.tool_use_id,
          content = item.content,
          is_error = item.is_error,
          is_user_declined = item.is_user_declined,
        }
      end
    end
  end
  return nil
end

return M
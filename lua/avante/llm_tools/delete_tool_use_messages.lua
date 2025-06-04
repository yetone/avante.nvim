local Base = require("avante.llm_tools.base")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "delete_tool_use_messages"

M.description =
  "Since many tool use messages are useless for completing subsequent tasks and may cause excessive token consumption or even prevent task completion, you need to decide whether to invoke this tool to delete the useless tool use messages."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "tool_use_id",
      description = "The tool use id",
      type = "string",
    },
  },
  usage = {
    tool_use_id = "The tool use id",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "True if the deletion was successful, false otherwise",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message",
    type = "string",
    optional = true,
  },
}

---@type AvanteLLMToolFunc<{ tool_use_id: string }>
function M.func(opts)
  local sidebar = require("avante").get()
  if not sidebar then return false, "Avante sidebar not found" end
  local history_messages = Utils.get_history_messages(sidebar.chat_history)
  local the_deleted_message_uuids = {}
  for _, msg in ipairs(history_messages) do
    if Utils.is_tool_use_message(msg) then
      local content = msg.message.content
      if type(content) == "table" then
        for _, item in ipairs(content) do
          if item.id == opts.tool_use_id then table.insert(the_deleted_message_uuids, msg.uuid) end
        end
      end
    end
  end
  sidebar:delete_history_messages(the_deleted_message_uuids)
  return true, nil
end

return M

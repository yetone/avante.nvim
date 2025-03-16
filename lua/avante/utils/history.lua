local Utils = require("avante.utils")
local Config = require("avante.config")

---@class avante.utils.history
local M = {}

---@param entries avante.ChatHistoryEntry[]
---@return avante.ChatHistoryEntry[]
function M.filter_active_entries(entries)
  local entries_ = {}

  for i = #entries, 1, -1 do
    local entry = entries[i]
    if entry.reset_memory then break end
    table.insert(entries_, 1, entry)
  end

  return entries_
end

---@param entries avante.ChatHistoryEntry[]
---@return AvanteLLMMessage[]
function M.entries_to_llm_messages(entries)
  local current_provider_name = Config.provider
  local messages = {}
  for _, entry in ipairs(entries) do
    if entry.selected_filepaths ~= nil and #entry.selected_filepaths > 0 then
      local user_content = "SELECTED FILES:\n\n"
      for _, filepath in ipairs(entry.selected_filepaths) do
        user_content = user_content .. filepath .. "\n"
      end
      table.insert(messages, { role = "user", content = user_content })
    end
    if entry.selected_code ~= nil then
      local user_content_ = "SELECTED CODE:\n\n```"
        .. (entry.selected_code.file_type or "")
        .. (entry.selected_code.path and ":" .. entry.selected_code.path or "")
        .. "\n"
        .. entry.selected_code.content
        .. "\n```\n\n"
      table.insert(messages, { role = "user", content = user_content_ })
    end
    if entry.request ~= nil and entry.request ~= "" then
      table.insert(messages, { role = "user", content = entry.request })
    end
    if entry.tool_histories ~= nil and #entry.tool_histories > 0 and entry.provider == current_provider_name then
      for _, tool_history in ipairs(entry.tool_histories) do
        local assistant_content = {}
        if tool_history.tool_use ~= nil then
          if tool_history.tool_use.response_contents ~= nil then
            for _, response_content in ipairs(tool_history.tool_use.response_contents) do
              table.insert(assistant_content, { type = "text", text = response_content })
            end
          end
          table.insert(assistant_content, {
            type = "tool_use",
            name = tool_history.tool_use.name,
            id = tool_history.tool_use.id,
            input = vim.json.decode(tool_history.tool_use.input_json),
          })
        end
        table.insert(messages, {
          role = "assistant",
          content = assistant_content,
        })
        local user_content = {}
        if tool_history.tool_result ~= nil and tool_history.tool_result.content ~= nil then
          table.insert(user_content, {
            type = "tool_result",
            tool_use_id = tool_history.tool_result.tool_use_id,
            content = tool_history.tool_result.content,
            is_error = tool_history.tool_result.is_error,
          })
        end
        table.insert(messages, {
          role = "user",
          content = user_content,
        })
      end
    end
    local assistant_content = Utils.trim_think_content(entry.original_response or "")
    if assistant_content ~= "" then table.insert(messages, { role = "assistant", content = assistant_content }) end
  end
  return messages
end

return M

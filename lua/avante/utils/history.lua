local Utils = require("avante.utils")

---@class avante.utils.history
local M = {}

---@param entries avante.ChatHistoryEntry[]
---@return avante.ChatHistoryEntry[]
function M.filter_active_entries(entries)
  local entries_ = {}

  for i = #entries, 1, -1 do
    local entry = entries[i]
    if entry.reset_memory then break end
    if
      entry.request == nil
      or entry.original_response == nil
      or entry.request == ""
      or entry.original_response == ""
    then
      break
    end
    table.insert(entries_, 1, entry)
  end

  return entries_
end

---@param entries avante.ChatHistoryEntry[]
---@return AvanteLLMMessage[]
function M.entries_to_llm_messages(entries)
  local messages = {}
  for _, entry in ipairs(entries) do
    local user_content = ""
    if entry.selected_file ~= nil then
      user_content = user_content .. "SELECTED FILE: " .. entry.selected_file.filepath .. "\n\n"
    end
    if entry.selected_code ~= nil then
      user_content = user_content
        .. "SELECTED CODE:\n\n```"
        .. entry.selected_code.filetype
        .. "\n"
        .. entry.selected_code.content
        .. "\n```\n\n"
    end
    user_content = user_content .. "USER PROMPT:\n\n" .. entry.request
    table.insert(messages, { role = "user", content = user_content })
    table.insert(messages, { role = "assistant", content = Utils.trim_think_content(entry.original_response) })
  end
  return messages
end

return M

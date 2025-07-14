local Helpers = require("avante.history.helpers")
local Message = require("avante.history.message")
local Utils = require("avante.utils")

local M = {}

M.Helpers = Helpers
M.Message = Message

---@param history avante.ChatHistory
---@return avante.HistoryMessage[]
function M.get_history_messages(history)
  if history.messages then return history.messages end
  local messages = {}
  for _, entry in ipairs(history.entries or {}) do
    if entry.request and entry.request ~= "" then
      local message = Message:new({
        role = "user",
        content = entry.request,
      }, {
        timestamp = entry.timestamp,
        is_user_submission = true,
        visible = entry.visible,
        selected_filepaths = entry.selected_filepaths,
        selected_code = entry.selected_code,
      })
      table.insert(messages, message)
    end
    if entry.response and entry.response ~= "" then
      local message = Message:new({
        role = "assistant",
        content = entry.response,
      }, {
        timestamp = entry.timestamp,
        visible = entry.visible,
      })
      table.insert(messages, message)
    end
  end
  history.messages = messages
  return messages
end

---@param messages avante.HistoryMessage[]
---@param using_ReAct_prompt boolean
---@param add_diagnostic boolean Mix in LSP diagnostic info for affected files
---@return avante.HistoryMessage[]
M.update_history_messages = function(messages, using_ReAct_prompt, add_diagnostic)
  local tool_id_to_tool_name = {}
  local tool_id_to_path = {}
  local tool_id_to_start_line = {}
  local tool_id_to_end_line = {}
  local viewed_files = {}
  local last_modified_files = {}
  local history_messages = {}

  for idx, message in ipairs(messages) do
    if Helpers.is_tool_result_message(message) then
      local tool_use_message = Helpers.get_tool_use_message(message, messages)

      local is_edit_func_call, _, _, path = Helpers.is_edit_func_call_message(tool_use_message)

      -- Only track as successful modification if not an error AND not user-declined
      if
        is_edit_func_call
        and path
        and not message.message.content[1].is_error
        and not message.message.content[1].is_user_declined
      then
        local uniformed_path = Utils.uniform_path(path)
        last_modified_files[uniformed_path] = idx
      end
    end
  end

  for idx, message in ipairs(messages) do
    table.insert(history_messages, message)
    if Helpers.is_tool_result_message(message) then
      local tool_use_message = Helpers.get_tool_use_message(message, messages)
      local is_edit_func_call, is_str_replace_editor_func_call, is_str_replace_based_edit_tool_func_call, path =
        Helpers.is_edit_func_call_message(tool_use_message)
      --- For models like gpt-4o, the input parameter of replace_in_file is treated as the latest file content, so here we need to insert a fake view tool call to ensure it uses the latest file content
      if is_edit_func_call and path and not message.message.content[1].is_error then
        local uniformed_path = Utils.uniform_path(path)
        local view_result, view_error = require("avante.llm_tools.view").func({ path = path }, {})
        if view_error then view_result = "Error: " .. view_error end
        local get_diagnostics_tool_use_id = Utils.uuid()
        local view_tool_use_id = Utils.uuid()
        local view_tool_name = "view"
        local view_tool_input = { path = path }
        if is_str_replace_editor_func_call then
          view_tool_name = "str_replace_editor"
          view_tool_input = { command = "view", path = path }
        end
        if is_str_replace_based_edit_tool_func_call then
          view_tool_name = "str_replace_based_edit_tool"
          view_tool_input = { command = "view", path = path }
        end
        history_messages = vim.list_extend(history_messages, {
          Message:new_assistant_synthetic(string.format("Viewing file %s to get the latest content", path)),
          Message:new_assistant_synthetic({
            type = "tool_use",
            id = view_tool_use_id,
            name = view_tool_name,
            input = view_tool_input,
          }),
          Message:new_user_synthetic({
            type = "tool_result",
            tool_use_id = view_tool_use_id,
            content = view_result,
            is_error = view_error ~= nil,
            is_user_declined = false,
          }),
        })
        if last_modified_files[uniformed_path] == idx and add_diagnostic then
          local diagnostics = Utils.lsp.get_diagnostics_from_filepath(path)
          history_messages = vim.list_extend(history_messages, {
            Message:new_assistant_synthetic(
              string.format(
                "The file %s has been modified, let me check if there are any errors in the changes.",
                path
              )
            ),
            Message:new_assistant_synthetic({
              type = "tool_use",
              id = get_diagnostics_tool_use_id,
              name = "get_diagnostics",
              input = { path = path },
            }),
            Message:new_user_synthetic({
              type = "tool_result",
              tool_use_id = get_diagnostics_tool_use_id,
              content = vim.json.encode(diagnostics),
              is_error = false,
              is_user_declined = false,
            }),
          })
        end
      end
    end
  end
  for _, message in ipairs(history_messages) do
    local content = message.message.content
    if type(content) ~= "table" then goto continue end
    for _, item in ipairs(content) do
      if type(item) ~= "table" then goto continue1 end
      if item.type ~= "tool_use" then goto continue1 end
      local tool_name = item.name
      if tool_name ~= "view" then goto continue1 end
      local path = item.input.path
      tool_id_to_tool_name[item.id] = tool_name
      if path then
        local uniform_path = Utils.uniform_path(path)
        tool_id_to_path[item.id] = uniform_path
        tool_id_to_start_line[item.id] = item.input.start_line
        tool_id_to_end_line[item.id] = item.input.end_line
        viewed_files[uniform_path] = item.id
      end
      ::continue1::
    end
    ::continue::
  end
  for _, message in ipairs(history_messages) do
    local content = message.message.content
    if type(content) == "table" then
      for _, item in ipairs(content) do
        if type(item) ~= "table" then goto continue end
        if item.type ~= "tool_result" then goto continue end
        local tool_name = tool_id_to_tool_name[item.tool_use_id]
        if tool_name ~= "view" then goto continue end
        if item.is_error then goto continue end
        local path = tool_id_to_path[item.tool_use_id]
        local latest_tool_id = viewed_files[path]
        if not latest_tool_id then goto continue end
        if latest_tool_id ~= item.tool_use_id then
          item.content = string.format("The file %s has been updated. Please use the latest `view` tool result!", path)
        else
          local start_line = tool_id_to_start_line[item.tool_use_id]
          local end_line = tool_id_to_end_line[item.tool_use_id]
          local view_result, view_error = require("avante.llm_tools.view").func(
            { path = path, start_line = start_line, end_line = end_line },
            {}
          )
          if view_error then view_result = "Error: " .. view_error end
          item.content = view_result
          item.is_error = view_error ~= nil
        end
        ::continue::
      end
    end
  end

  if not using_ReAct_prompt then
    local picked_messages = {}
    local max_tool_use_count = 25
    local tool_use_count = 0
    for idx = #history_messages, 1, -1 do
      local msg = history_messages[idx]
      if tool_use_count > max_tool_use_count then
        if Helpers.is_tool_result_message(msg) then
          local tool_use_message = Helpers.get_tool_use_message(msg, history_messages)
          if tool_use_message then
            table.insert(
              picked_messages,
              1,
              Message:new_user_synthetic({
                type = "text",
                text = string.format(
                  "Tool use [%s] is successful: %s",
                  tool_use_message.message.content[1].name,
                  tostring(not msg.message.content[1].is_error)
                ),
              })
            )
            table.insert(
              picked_messages,
              1,
              Message:new_assistant_synthetic({
                type = "text",
                text = string.format(
                  "Tool use %s(%s)",
                  tool_use_message.message.content[1].name,
                  vim.json.encode(tool_use_message.message.content[1].input)
                ),
              })
            )
          end
        elseif Helpers.is_tool_use_message(msg) then
          tool_use_count = tool_use_count + 1
          goto continue
        else
          table.insert(picked_messages, 1, msg)
        end
      else
        if Helpers.is_tool_use_message(msg) then tool_use_count = tool_use_count + 1 end
        table.insert(picked_messages, 1, msg)
      end
      ::continue::
    end

    history_messages = picked_messages
  end

  local final_history_messages = {}
  for _, msg in ipairs(history_messages) do
    local tool_result_message
    if Helpers.is_tool_use_message(msg) then
      tool_result_message = Helpers.get_tool_result_message(msg, history_messages)
      if not tool_result_message then goto continue end
    end
    if Helpers.is_tool_result_message(msg) then goto continue end
    table.insert(final_history_messages, msg)
    if tool_result_message then table.insert(final_history_messages, tool_result_message) end
    ::continue::
  end

  return final_history_messages
end

---Scans message history backwards, looking for tool invocations that have not been executed yet
---@param messages avante.HistoryMessage[]
---@return AvantePartialLLMToolUse[]
---@return avante.HistoryMessage[]
function M.get_pending_tools(messages)
  local last_turn_id = nil
  if #messages > 0 then last_turn_id = messages[#messages].turn_id end

  local pending_tool_uses = {} ---@type AvantePartialLLMToolUse[]
  local pending_tool_uses_messages = {} ---@type avante.HistoryMessage[]
  local tool_result_seen = {}

  for idx = #messages, 1, -1 do
    local message = messages[idx]

    if last_turn_id and message.turn_id ~= last_turn_id then break end

    local use = Helpers.get_tool_use_data(message)
    if use then
      if not tool_result_seen[use.id] then
        local partial_tool_use = {
          name = use.name,
          id = use.id,
          input = use.input,
          state = message.state,
        }
        table.insert(pending_tool_uses, 1, partial_tool_use)
        table.insert(pending_tool_uses_messages, 1, message)
      end
      goto continue
    end

    local result = Helpers.get_tool_result_data(message)
    if result then tool_result_seen[result.tool_use_id] = true end

    ::continue::
  end

  return pending_tool_uses, pending_tool_uses_messages
end

return M

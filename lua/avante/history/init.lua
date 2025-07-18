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
      local message = Message:new("user", entry.request, {
        timestamp = entry.timestamp,
        is_user_submission = true,
        visible = entry.visible,
        selected_filepaths = entry.selected_filepaths,
        selected_code = entry.selected_code,
      })
      table.insert(messages, message)
    end
    if entry.response and entry.response ~= "" then
      local message = Message:new("assistant", entry.response, {
        timestamp = entry.timestamp,
        visible = entry.visible,
      })
      table.insert(messages, message)
    end
  end
  history.messages = messages
  return messages
end

---Represents information about tool use: invocation, result, affected file (for "view" or "edit" tools).
---@class HistoryToolInfo
---@field kind "edit" | "view" | "other"
---@field use AvanteLLMToolUse
---@field result? AvanteLLMToolResult
---@field result_message? avante.HistoryMessage Complete result message
---@field path? string Uniform (normalized) path of the affected file

---@class HistoryFileInfo
---@field last_tool_id? string ID of the tool with most up-to-date state of the file
---@field edit_tool_id? string ID of the last tool done edit on the file

---Collects information about all uses of tools in the history: their invocations, results, and affected files.
---@param messages avante.HistoryMessage[]
---@return table<string, HistoryToolInfo>
---@return table<string, HistoryFileInfo>
local function collect_tool_info(messages)
  ---@type table<string, HistoryToolInfo> Maps tool ID to tool information
  local tools = {}
  ---@type table<string, HistoryFileInfo> Maps file path to file information
  local files = {}

  -- Collect invocations of all tools, and also build a list of viewed or edited files.
  for _, message in ipairs(messages) do
    local use = Helpers.get_tool_use_data(message)
    if use then
      if use.name == "view" or Utils.is_edit_tool_use(use) then
        if use.input.path then
          local path = Utils.uniform_path(use.input.path)
          tools[use.id] = { kind = use.name == "view" and "view" or "edit", use = use, path = path }
        end
      else
        tools[use.id] = { kind = "other", use = use }
      end
      goto continue
    end

    local result = Helpers.get_tool_result_data(message)
    if result then
      -- We assume that "result" entries always come after corresponding "use" entries.
      local info = tools[result.tool_use_id]
      if info then
        info.result = result
        info.result_message = message
        if info.path then
          local f = files[info.path]
          if not f then
            f = {}
            files[info.path] = f
          end
          f.last_tool_id = result.tool_use_id
          if info.kind == "edit" and not (result.is_error or result.is_user_declined) then
            f.edit_tool_id = result.tool_use_id
          end
        end
      end
    end

    ::continue::
  end

  return tools, files
end

---Converts a tool invocation (use + result) into a simple request/response pair of text messages
---@param tool_info HistoryToolInfo
---@return avante.HistoryMessage[]
local function convert_tool_to_text(tool_info)
  return {
    Message:new_assistant_synthetic(
      string.format("Tool use %s(%s)", tool_info.use.name, vim.json.encode(tool_info.use.input))
    ),
    Message:new_user_synthetic({
      type = "text",
      text = string.format(
        "Tool use [%s] is successful: %s",
        tool_info.use.name,
        tostring(not tool_info.result.is_error)
      ),
    }),
  }
end

---Generates a fake file "content" telling LLM to look further for up-to-date data
---@param path string
---@return string
local function stale_view_content(path)
  return string.format("The file %s has been updated. Please use the latest `view` tool result!", path)
end

---Updates the result of "view" tool invocation with latest contents of a buffer or file,
---or a stub message if this result will be superseded by another one.
---@param tool_info HistoryToolInfo
---@param stale_view boolean
local function update_view_result(tool_info, stale_view)
  local use = tool_info.use
  local result = tool_info.result

  if stale_view then
    result.content = stale_view_content(tool_info.path)
  else
    local view_result, view_error = require("avante.llm_tools.view").func(
      { path = tool_info.path, start_line = use.input.start_line, end_line = use.input.end_line },
      {}
    )
    result.content = view_error and ("Error: " .. view_error) or view_result
    result.is_error = view_error ~= nil
  end
end

---Generates synthetic "view" tool invocation to tell LLM to refresh its view of a file after editing
---@param tool_use AvanteLLMToolUse
---@param path any
---@param stale_view any
---@return avante.HistoryMessage[]
local function generate_view_messages(tool_use, path, stale_view)
  local view_result, view_error
  if stale_view then
    view_result = stale_view_content(path)
  else
    view_result, view_error = require("avante.llm_tools.view").func({ path = path }, {})
  end

  if view_error then view_result = "Error: " .. view_error end

  local view_tool_use_id = Utils.uuid()
  local view_tool_name = "view"
  local view_tool_input = { path = path }

  if tool_use.name == "str_replace_editor" and tool_use.input.command == "str_replace" then
    view_tool_name = "str_replace_editor"
    view_tool_input.command = "view"
  elseif tool_use.name == "str_replace_based_edit_tool" and tool_use.input.command == "str_replace" then
    view_tool_name = "str_replace_based_edit_tool"
    view_tool_input.command = "view"
  end

  return {
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
  }
end

---Generates "diagnostic" for a file after it has been edited to help catching errors
---@param path string
---@return avante.HistoryMessage[]
local function generate_diagnostic_messages(path)
  local get_diagnostics_tool_use_id = Utils.uuid()
  local diagnostics = Utils.lsp.get_diagnostics_from_filepath(path)
  return {
    Message:new_assistant_synthetic(
      string.format("The file %s has been modified, let me check if there are any errors in the changes.", path)
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
  }
end

---Iterate through history messages and generate a new list containing updated history
---that has up-to-date file contents and potentially updated diagnostic for modified
---files.
---@param messages avante.HistoryMessage[]
---@param tools HistoryToolInfo[]
---@param files HistoryFileInfo[]
---@param add_diagnostic boolean Whether to generate and add diagnostic info to "edit" invocations
---@param tools_to_text integer Number of tool invocations to be converted to simple text
---@return avante.HistoryMessage[]
local function refresh_history(messages, tools, files, add_diagnostic, tools_to_text)
  ---@type avante.HistoryMessage[]
  local updated_messages = {}
  local tool_count = 0

  for _, message in ipairs(messages) do
    local use = Helpers.get_tool_use_data(message)
    if use then
      -- This is a tool invocation message. We will be handling both use and result together.
      local tool_info = tools[use.id]
      if not tool_info then goto continue end
      if not tool_info.result then goto continue end

      if tool_count < tools_to_text then
        local text_msgs = convert_tool_to_text(tool_info)
        Utils.debug("Converted", use.name, "invocation to", #text_msgs, "messages")
        updated_messages = vim.list_extend(updated_messages, text_msgs)
      else
        table.insert(updated_messages, message)
        table.insert(updated_messages, tool_info.result_message)
        tool_count = tool_count + 1

        if tool_info.kind == "view" then
          local path = tool_info.path
          assert(path, "encountered 'view' tool invocation without path")
          update_view_result(tool_info, use.id ~= files[tool_info.path].last_tool_id)
        end
      end

      if tool_info.kind == "edit" then
        local path = tool_info.path
        assert(path, "encountered 'edit' tool invocation without path")
        local file_info = files[path]

        -- If this is the last operation for this file, generate synthetic "view"
        -- invocation to provide the up-to-date file contents.
        if not tool_info.result.is_error then
          local view_msgs = generate_view_messages(use, path, use.id == file_info.last_tool_id)
          Utils.debug("Added", #view_msgs, "'view' tool messages for", path)
          updated_messages = vim.list_extend(updated_messages, view_msgs)
          tool_count = tool_count + 1
        end

        if add_diagnostic and use.id == file_info.edit_tool_id then
          local diag_msgs = generate_diagnostic_messages(path)
          Utils.debug("Added", #diag_msgs, "'diagnostics' tool messages for", path)
          updated_messages = vim.list_extend(updated_messages, diag_msgs)
          tool_count = tool_count + 1
        end
      end
    elseif not Helpers.get_tool_result_data(message) then
      -- Skip the tool result messages (since we process them together with their "use"s.
      -- All other (non-tool-related) messages we simply keep.
      table.insert(updated_messages, message)
    end

    ::continue::
  end

  return updated_messages
end

---Analyzes the history looking for tool invocations, drops incomplete invocations,
---and updates complete ones with the latest data available.
---@param messages avante.HistoryMessage[]
---@param max_tool_use integer | nil Maximum number of tool invocations to keep
---@param add_diagnostic boolean Mix in LSP diagnostic info for affected files
---@return avante.HistoryMessage[]
M.update_tool_invocation_history = function(messages, max_tool_use, add_diagnostic)
  local tools, files = collect_tool_info(messages)

  -- Figure number of tool invocations that should be converted to simple "text"
  -- messages to reduce prompt costs.
  local tools_to_text = 0
  if max_tool_use then
    local n_edits = vim.iter(files):fold(
      0,
      ---@param count integer
      ---@param file_info HistoryFileInfo
      function(count, file_info)
        if file_info.edit_tool_id then count = count + 1 end
        return count
      end
    )
    -- Each valid "edit" invocation will result in synthetic "view" and also
    -- in "diagnostic" if it is requested by the caller.
    local expected = #tools + n_edits + (add_diagnostic and n_edits or 0)
    tools_to_text = expected - max_tool_use
  end

  return refresh_history(messages, tools, files, add_diagnostic, tools_to_text)
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

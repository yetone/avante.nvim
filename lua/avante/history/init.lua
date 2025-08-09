local Helpers = require("avante.history.helpers")
local Message = require("avante.history.message")
local StorageIntegration = require("avante.history.storage_integration")
local Utils = require("avante.utils")

local M = {}

M.Helpers = Helpers
M.Message = Message
M.StorageIntegration = StorageIntegration

---🔄 Enhanced get_history_messages with new storage backend
---@param history avante.ChatHistory | avante.storage.UnifiedChatHistory
---@return avante.HistoryMessage[]
function M.get_history_messages(history)
  -- 🚀 Use enhanced storage integration that handles both legacy and new formats
  return StorageIntegration.get_history_messages(history)
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
          if use.id then tools[use.id] = { kind = use.name == "view" and "view" or "edit", use = use, path = path } end
        end
      else
        if use.id then tools[use.id] = { kind = "other", use = use } end
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

---🔄 Enhanced tool invocation history with new storage optimizations
---Analyzes the history looking for tool invocations, drops incomplete invocations,
---and updates complete ones with the latest data available.
---@param messages avante.HistoryMessage[]
---@param max_tool_use integer | nil Maximum number of tool invocations to keep
---@param add_diagnostic boolean Mix in LSP diagnostic info for affected files
---@return avante.HistoryMessage[]
M.update_tool_invocation_history = function(messages, max_tool_use, add_diagnostic)
  -- 🚀 Use enhanced storage integration that preserves all original logic
  -- while providing performance optimizations
  return StorageIntegration.update_tool_invocation_history(messages, max_tool_use, add_diagnostic)
end

---🔍 Enhanced pending tools detection with new storage optimizations
---Scans message history backwards, looking for tool invocations that have not been executed yet
---@param messages avante.HistoryMessage[]
---@return AvantePartialLLMToolUse[]
---@return avante.HistoryMessage[]
function M.get_pending_tools(messages)
  -- 🚀 Use enhanced storage integration with performance optimizations
  return StorageIntegration.get_pending_tools(messages)
end

---🚀 New storage API functions

---💾 Save history using new storage system
---@param history avante.ChatHistory | avante.storage.UnifiedChatHistory
---@param project_name string
---@return boolean success
---@return string? error_message
function M.save_history(history, project_name)
  return StorageIntegration.save_history(history, project_name)
end

---📖 Load history using new storage system
---@param history_id string
---@param project_name string
---@return avante.ChatHistory? history
---@return string? error_message
function M.load_history(history_id, project_name)
  return StorageIntegration.load_history(history_id, project_name)
end

---📋 List histories using new storage system
---@param project_name string
---@param opts? table Listing options
---@return table[] histories
---@return string? error_message
function M.list_histories(project_name, opts)
  return StorageIntegration.list_histories(project_name, opts)
end

---🔍 Search histories using new query system
---@param query table Search parameters
---@param project_name? string Optional project filter
---@return table[] results
---@return string? error_message
function M.search_histories(query, project_name)
  return StorageIntegration.search_histories(query, project_name)
end

---📊 Get storage statistics
---@param project_name? string
---@return table stats
function M.get_storage_stats(project_name)
  return StorageIntegration.get_storage_stats(project_name)
end

---✅ Perform storage health check
---@return boolean healthy
---@return table report
function M.storage_health_check()
  return StorageIntegration.storage_health_check()
end

---🔄 Trigger manual migration for a project
---@param project_name string
---@return boolean success
---@return table migration_summary
function M.migrate_project(project_name)
  return StorageIntegration.migrate_project(project_name)
end

---🧹 Manual cleanup for a project
---@param project_name string
---@return boolean success
---@return table cleanup_report
function M.cleanup_project(project_name)
  return StorageIntegration.cleanup_project(project_name)
end

---⚙️ Initialize storage system with configuration
---@param config? table Storage configuration from avante config
---@return boolean success
---@return string? error_message
function M.initialize_storage(config)
  return StorageIntegration.initialize(config)
end

---📦 Archive a specific conversation manually
---@param history_id string
---@param project_name string
---@return boolean success
---@return string? error_message
function M.archive_conversation(history_id, project_name)
  return StorageIntegration.archive_conversation(history_id, project_name)
end

---📦 Restore conversation from archive
---@param history_id string
---@param project_name string
---@return boolean success
---@return string? error_message
function M.restore_conversation(history_id, project_name)
  return StorageIntegration.restore_conversation(history_id, project_name)
end

---📋 List archived conversations for a project
---@param project_name string
---@return table[] archived_histories
---@return string? error_message
function M.list_archived_conversations(project_name)
  return StorageIntegration.list_archived_conversations(project_name)
end

---🧹 Get cleanup engine statistics
---@return table stats
function M.get_cleanup_stats()
  return StorageIntegration.get_cleanup_stats()
end

return M

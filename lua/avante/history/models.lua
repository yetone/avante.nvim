local Utils = require("avante.utils")

---@class avante.history.models
local M = {}

-- 📋 Schema versioning for backward compatibility
M.SCHEMA_VERSION = "1.0.0"
M.LEGACY_FORMAT_MARKER = "entries" -- 📌 Legacy format marker

---@class avante.UnifiedHistoryMessage
---@field uuid string Unique identifier for the message
---@field role "user" | "assistant" The role of the message sender
---@field content AvanteLLMMessageContentItem | string The message content
---@field timestamp number Unix timestamp when message was created
---@field turn_id? string Optional turn identifier for grouping related messages
---@field state? avante.HistoryMessageState State of the message (pending, streaming, generated, error)
---@field metadata table<string, any> Extensible metadata storage
---@field tool_info? HistoryToolInfo Associated tool information if this is a tool-related message
---@field file_info? HistoryFileInfo Associated file information if this affects files
---@field is_synthetic? boolean Whether this is a synthetic message (generated for context)
---@field is_user_submission? boolean Whether this represents user input
---@field visible? boolean Whether this message should be displayed in UI
---@field selected_code? AvanteSelectedCode Code selected when message was created
---@field selected_filepaths? string[] Files selected when message was created

---@class avante.UnifiedChatHistory
---@field schema_version string Version identifier for the data format
---@field uuid string Unique identifier for the conversation
---@field title string Human-readable title for the conversation
---@field messages avante.UnifiedHistoryMessage[] Array of conversation messages
---@field created_at number Unix timestamp when history was created
---@field updated_at number Unix timestamp when history was last modified
---@field metadata table<string, any> Conversation-level metadata
---@field project_info table Project context information
---@field project_info.root_path string Project root directory
---@field project_info.relative_path? string Relative path within project
---@field statistics table Usage statistics
---@field statistics.message_count number Total number of messages
---@field statistics.tool_invocations number Number of tool calls
---@field statistics.file_modifications number Number of file edits
---@field tags? string[] Optional tags for categorization
---@field archived? boolean Whether this conversation is archived
---@field filename? string Filename on disk (populated during load/save)

---🏗️ Creates a new UnifiedHistoryMessage instance
---@param role "user" | "assistant"
---@param content AvanteLLMMessageContentItem | string
---@param opts? table Optional parameters
---@return avante.UnifiedHistoryMessage
function M.create_message(role, content, opts)
  opts = opts or {}
  
  ---@type avante.UnifiedHistoryMessage
  local message = {
    uuid = opts.uuid or Utils.uuid(),
    role = role,
    content = content,
    timestamp = opts.timestamp or Utils.get_timestamp(),
    turn_id = opts.turn_id,
    state = opts.state or "generated",
    metadata = opts.metadata or {},
    tool_info = opts.tool_info,
    file_info = opts.file_info,
    is_synthetic = opts.is_synthetic or false,
    is_user_submission = opts.is_user_submission or false,
    visible = opts.visible ~= false, -- 📌 Default to visible unless explicitly hidden
    selected_code = opts.selected_code,
    selected_filepaths = opts.selected_filepaths,
  }
  
  return message
end

---🏗️ Creates a new UnifiedChatHistory instance
---@param opts? table Optional parameters
---@return avante.UnifiedChatHistory
function M.create_history(opts)
  opts = opts or {}
  local timestamp = Utils.get_timestamp()
  
  ---@type avante.UnifiedChatHistory
  local history = {
    schema_version = M.SCHEMA_VERSION,
    uuid = opts.uuid or Utils.uuid(),
    title = opts.title or "Untitled Conversation",
    messages = opts.messages or {},
    created_at = opts.created_at or timestamp,
    updated_at = opts.updated_at or timestamp,
    metadata = opts.metadata or {},
    project_info = opts.project_info or {
      root_path = Utils.root.get(),
      relative_path = nil,
    },
    statistics = {
      message_count = 0,
      tool_invocations = 0,
      file_modifications = 0,
    },
    tags = opts.tags,
    archived = opts.archived or false,
    filename = opts.filename,
  }
  
  -- 📊 Update statistics
  M.update_statistics(history)
  
  return history
end

---📊 Updates conversation statistics based on current messages
---@param history avante.UnifiedChatHistory
function M.update_statistics(history)
  local Helpers = require("avante.history.helpers")
  
  history.statistics.message_count = #history.messages
  history.statistics.tool_invocations = 0
  history.statistics.file_modifications = 0
  
  for _, message in ipairs(history.messages) do
    local use = Helpers.get_tool_use_data(message)
    if use then
      history.statistics.tool_invocations = history.statistics.tool_invocations + 1
      if Utils.is_edit_tool_use(use) then
        history.statistics.file_modifications = history.statistics.file_modifications + 1
      end
    end
  end
  
  history.updated_at = Utils.get_timestamp()
end

---🔄 Converts legacy ChatHistoryEntry format to UnifiedChatHistory
---@param legacy_history table Legacy history in old format
---@return avante.UnifiedChatHistory
function M.migrate_from_legacy(legacy_history)
  local Message = require("avante.history.message")
  
  -- 📌 Check if this is already a unified format
  if legacy_history.schema_version then
    return legacy_history
  end
  
  -- 🔄 Convert legacy entries to unified messages
  local messages = {}
  
  if legacy_history.entries then
    for _, entry in ipairs(legacy_history.entries) do
      if entry.request and entry.request ~= "" then
        local user_message = M.create_message("user", entry.request, {
          timestamp = entry.timestamp,
          is_user_submission = true,
          visible = entry.visible,
          selected_filepaths = entry.selected_filepaths,
          selected_code = entry.selected_code,
        })
        table.insert(messages, user_message)
      end
      
      if entry.response and entry.response ~= "" then
        local assistant_message = M.create_message("assistant", entry.response, {
          timestamp = entry.timestamp,
          visible = entry.visible,
        })
        table.insert(messages, assistant_message)
      end
    end
  elseif legacy_history.messages then
    -- 📌 Handle case where it's partially migrated (has messages but no schema_version)
    for _, message in ipairs(legacy_history.messages) do
      local unified_message = M.create_message(message.role or message.message.role, 
                                             message.content or message.message.content, {
        uuid = message.uuid,
        timestamp = message.timestamp,
        turn_id = message.turn_id,
        state = message.state,
        metadata = message.metadata or {},
        is_synthetic = message.is_dummy,
        is_user_submission = message.is_user_submission,
        visible = message.visible,
        selected_code = message.selected_code,
        selected_filepaths = message.selected_filepaths,
      })
      table.insert(messages, unified_message)
    end
  end
  
  -- 🏗️ Create unified history
  local unified_history = M.create_history({
    uuid = legacy_history.uuid,
    title = legacy_history.title or "Migrated Conversation",
    messages = messages,
    created_at = legacy_history.timestamp or legacy_history.created_at,
    filename = legacy_history.filename,
    metadata = {
      migrated_from = "legacy_format",
      migration_timestamp = Utils.get_timestamp(),
      original_format = legacy_history.entries and "ChatHistoryEntry" or "PartialUnified",
    },
  })
  
  return unified_history
end

---🔍 Detects if a history object is in legacy format
---@param history table
---@return boolean
function M.is_legacy_format(history)
  return history.entries ~= nil or (history.messages ~= nil and not history.schema_version)
end

---🧹 Validates UnifiedChatHistory structure and fixes issues
---@param history avante.UnifiedChatHistory
---@return avante.UnifiedChatHistory, string[] List of validation warnings
function M.validate_and_fix(history)
  local warnings = {}
  
  -- 🔧 Ensure required fields exist
  if not history.schema_version then
    history.schema_version = M.SCHEMA_VERSION
    table.insert(warnings, "Added missing schema_version")
  end
  
  if not history.uuid then
    history.uuid = Utils.uuid()
    table.insert(warnings, "Generated missing UUID")
  end
  
  if not history.messages then
    history.messages = {}
    table.insert(warnings, "Initialized missing messages array")
  end
  
  if not history.statistics then
    history.statistics = {
      message_count = 0,
      tool_invocations = 0,
      file_modifications = 0,
    }
    table.insert(warnings, "Initialized missing statistics")
  end
  
  if not history.project_info then
    history.project_info = {
      root_path = Utils.root.get(),
    }
    table.insert(warnings, "Initialized missing project_info")
  end
  
  if not history.metadata then
    history.metadata = {}
    table.insert(warnings, "Initialized missing metadata")
  end
  
  -- 🔧 Fix message UUIDs if missing
  for i, message in ipairs(history.messages) do
    if not message.uuid then
      message.uuid = Utils.uuid()
      table.insert(warnings, string.format("Generated UUID for message %d", i))
    end
  end
  
  -- 📊 Update statistics
  M.update_statistics(history)
  
  return history, warnings
end

---🔗 Converts UnifiedHistoryMessage to legacy HistoryMessage format for compatibility
---@param unified_message avante.UnifiedHistoryMessage
---@return avante.HistoryMessage
function M.to_legacy_message(unified_message)
  local Message = require("avante.history.message")
  
  return Message:new(unified_message.role, unified_message.content, {
    uuid = unified_message.uuid,
    turn_id = unified_message.turn_id,
    state = unified_message.state,
    timestamp = unified_message.timestamp,
    is_user_submission = unified_message.is_user_submission,
    visible = unified_message.visible,
    selected_code = unified_message.selected_code,
    selected_filepaths = unified_message.selected_filepaths,
    is_dummy = unified_message.is_synthetic,
  })
end

---🔄 Converts array of UnifiedHistoryMessage to legacy HistoryMessage format
---@param unified_messages avante.UnifiedHistoryMessage[]
---@return avante.HistoryMessage[]
function M.to_legacy_messages(unified_messages)
  local legacy_messages = {}
  for _, message in ipairs(unified_messages) do
    table.insert(legacy_messages, M.to_legacy_message(message))
  end
  return legacy_messages
end

return M
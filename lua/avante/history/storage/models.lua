local Utils = require("avante.utils")

---@class avante.storage.UnifiedHistoryMessage
---@field uuid string 📝 Unique identifier for this message
---@field version string 🔄 Schema version for backward compatibility
---@field role "user" | "assistant" 👤 Message role
---@field content AvanteLLMMessageContent 💬 Message content (can be string or structured)
---@field timestamp string ⏰ ISO timestamp when message was created
---@field turn_id? string 🔄 Turn identifier for grouping related messages
---@field state? avante.HistoryMessageState 📊 Current message state
---@field metadata table 📋 Extended metadata storage
---@field tool_info? table 🛠️ Tool execution information if applicable
---@field display_info? table 🎨 Display-related information
---@field provider_info? table 🏭 Provider-specific information

---@class avante.storage.UnifiedChatHistory
---@field uuid string 📝 Unique identifier for this chat history
---@field version string 🔄 Schema version for compatibility
---@field created_at string ⏰ ISO timestamp when history was created
---@field updated_at string 📅 ISO timestamp when history was last updated
---@field project_name string 🏗️ Project this history belongs to
---@field messages avante.storage.UnifiedHistoryMessage[] 💬 Array of history messages
---@field metadata table 📋 Additional metadata for the chat
---@field stats table 📊 Statistics about the chat (token counts, etc.)

local M = {}

---📝 Current schema version for unified history format
M.SCHEMA_VERSION = "2.0.0"

---🏗️ Create a new UnifiedHistoryMessage instance
---@param role "user" | "assistant"
---@param content AvanteLLMMessageContent
---@param opts? table Optional parameters
---@return avante.storage.UnifiedHistoryMessage
function M.create_unified_message(role, content, opts)
  opts = opts or {}
  
  return {
    uuid = opts.uuid or Utils.uuid(),
    version = M.SCHEMA_VERSION,
    role = role,
    content = content,
    timestamp = opts.timestamp or Utils.get_timestamp(),
    turn_id = opts.turn_id,
    state = opts.state or "generated",
    metadata = {
      visible = opts.visible ~= false,
      is_user_submission = opts.is_user_submission or false,
      is_dummy = opts.is_dummy or false,
      is_context = opts.is_context or false,
      selected_code = opts.selected_code,
      selected_filepaths = opts.selected_filepaths,
      original_content = opts.original_content,
      displayed_content = opts.displayed_content,
    },
    tool_info = opts.tool_info,
    display_info = opts.display_info or {},
    provider_info = opts.provider_info or {
      provider = opts.provider,
      model = opts.model,
    },
  }
end

---🏗️ Create a new UnifiedChatHistory instance
---@param project_name string
---@param opts? table Optional parameters
---@return avante.storage.UnifiedChatHistory
function M.create_unified_history(project_name, opts)
  opts = opts or {}
  
  return {
    uuid = opts.uuid or Utils.uuid(),
    version = M.SCHEMA_VERSION,
    created_at = opts.created_at or Utils.get_timestamp(),
    updated_at = opts.updated_at or Utils.get_timestamp(),
    project_name = project_name,
    messages = opts.messages or {},
    metadata = opts.metadata or {},
    stats = opts.stats or {
      total_messages = 0,
      total_tokens = 0,
      last_activity = Utils.get_timestamp(),
    },
  }
end

---🔄 Convert legacy ChatHistoryEntry format to UnifiedHistoryMessage format
---@param entry table Legacy ChatHistoryEntry
---@return avante.storage.UnifiedHistoryMessage[]
function M.convert_legacy_entry(entry)
  local messages = {}
  
  -- 💬 Convert request message if present
  if entry.request and entry.request ~= "" then
    local user_message = M.create_unified_message("user", entry.request, {
      timestamp = entry.timestamp,
      is_user_submission = true,
      visible = entry.visible,
      selected_code = entry.selected_code,
      selected_filepaths = entry.selected_filepaths,
    })
    table.insert(messages, user_message)
  end
  
  -- 🤖 Convert response message if present
  if entry.response and entry.response ~= "" then
    local assistant_message = M.create_unified_message("assistant", entry.response, {
      timestamp = entry.timestamp,
      visible = entry.visible,
    })
    table.insert(messages, assistant_message)
  end
  
  return messages
end

---🔄 Convert legacy ChatHistory format to UnifiedChatHistory format
---@param legacy_history table Legacy ChatHistory object
---@param project_name string Project name for the history
---@return avante.storage.UnifiedChatHistory
function M.convert_legacy_history(legacy_history, project_name)
  local unified_history = M.create_unified_history(project_name)
  
  -- 🔄 If already has messages array, use it directly (partial migration)
  if legacy_history.messages then
    for _, message in ipairs(legacy_history.messages) do
      -- 📝 Convert existing HistoryMessage to UnifiedHistoryMessage if needed
      if not message.version then
        local unified_message = M.create_unified_message(
          message.message.role,
          message.message.content,
          {
            uuid = message.uuid,
            timestamp = message.timestamp,
            turn_id = message.turn_id,
            state = message.state,
            visible = message.visible,
            is_user_submission = message.is_user_submission,
            is_dummy = message.is_dummy,
            is_context = message.is_context,
            selected_code = message.selected_code,
            selected_filepaths = message.selected_filepaths,
            original_content = message.original_content,
            displayed_content = message.displayed_content,
            provider = message.provider,
            model = message.model,
          }
        )
        table.insert(unified_history.messages, unified_message)
      else
        table.insert(unified_history.messages, message)
      end
    end
  else
    -- 🔄 Convert legacy entries format
    for _, entry in ipairs(legacy_history.entries or {}) do
      local converted_messages = M.convert_legacy_entry(entry)
      for _, msg in ipairs(converted_messages) do
        table.insert(unified_history.messages, msg)
      end
    end
  end
  
  -- 📊 Update statistics
  unified_history.stats.total_messages = #unified_history.messages
  unified_history.stats.last_activity = unified_history.updated_at
  
  return unified_history
end

---✅ Validate a UnifiedHistoryMessage
---@param message table
---@return boolean, string? is_valid, error_message
function M.validate_unified_message(message)
  if type(message) ~= "table" then
    return false, "Message must be a table"
  end
  
  if not message.uuid or type(message.uuid) ~= "string" then
    return false, "Message must have a valid UUID"
  end
  
  if not message.version or type(message.version) ~= "string" then
    return false, "Message must have a version string"
  end
  
  if not message.role or (message.role ~= "user" and message.role ~= "assistant") then
    return false, "Message must have a valid role (user or assistant)"
  end
  
  if not message.content then
    return false, "Message must have content"
  end
  
  if not message.timestamp or type(message.timestamp) ~= "string" then
    return false, "Message must have a valid timestamp"
  end
  
  return true
end

---✅ Validate a UnifiedChatHistory
---@param history table
---@return boolean, string? is_valid, error_message
function M.validate_unified_history(history)
  if type(history) ~= "table" then
    return false, "History must be a table"
  end
  
  if not history.uuid or type(history.uuid) ~= "string" then
    return false, "History must have a valid UUID"
  end
  
  if not history.version or type(history.version) ~= "string" then
    return false, "History must have a version string"
  end
  
  if not history.project_name or type(history.project_name) ~= "string" then
    return false, "History must have a valid project name"
  end
  
  if not history.messages or type(history.messages) ~= "table" then
    return false, "History must have a messages array"
  end
  
  -- 📝 Validate each message
  for i, message in ipairs(history.messages) do
    local is_valid, error_msg = M.validate_unified_message(message)
    if not is_valid then
      return false, string.format("Message %d is invalid: %s", i, error_msg)
    end
  end
  
  return true
end

---🔧 Update message metadata
---@param message avante.storage.UnifiedHistoryMessage
---@param updates table
function M.update_message_metadata(message, updates)
  message.metadata = vim.tbl_deep_extend("force", message.metadata, updates)
  -- 📅 Update timestamp to track modification
  message.updated_at = Utils.get_timestamp()
end

---📊 Update history statistics
---@param history avante.storage.UnifiedChatHistory
function M.update_history_stats(history)
  history.stats.total_messages = #history.messages
  history.stats.last_activity = Utils.get_timestamp()
  history.updated_at = Utils.get_timestamp()
  
  -- 🔢 Calculate token estimates if available
  local total_tokens = 0
  for _, message in ipairs(history.messages) do
    if message.metadata and message.metadata.token_count then
      total_tokens = total_tokens + message.metadata.token_count
    end
  end
  history.stats.total_tokens = total_tokens
end

return M
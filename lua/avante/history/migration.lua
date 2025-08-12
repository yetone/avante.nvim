local Utils = require("avante.utils")
local Message = require("avante.history.message")
local Path = require("plenary.path")

---@class avante.HistoryMigration
local M = {}

--- 🔄 Migration metadata tracking structure
---@class avante.MigrationMetadata
---@field version number Current data version
---@field format "unified" | "legacy" Data format type
---@field migrated_at string Migration timestamp
---@field original_format "ChatHistoryEntry" | "HistoryMessage" Original format identifier
---@field migration_uuid string Unique migration identifier
---@field backup_path string | nil Path to backup file if created

--- 📋 Unified chat history schema with enhanced metadata
---@class avante.UnifiedChatHistory : avante.ChatHistory
---@field migration_metadata avante.MigrationMetadata | nil Migration tracking info
---@field version number Data version (default: 2)

--- 🚀 Migration engine constants
M.CURRENT_VERSION = 2
M.LEGACY_VERSION = 1
M.BACKUP_SUFFIX = ".backup"
M.MIGRATION_LOG_FILE = "migration.log"

--- 🔍 Detects if history data is in legacy format
---@param history avante.ChatHistory
---@return boolean is_legacy True if history uses legacy ChatHistoryEntry format
function M.is_legacy_format(history)
  -- 📝 Legacy format has 'entries' field instead of 'messages'
  return history.entries ~= nil and history.messages == nil
end

--- 📊 Detects the version of history data
---@param history avante.ChatHistory
---@return number version Data version number
function M.detect_version(history)
  if history.version then
    return history.version
  end
  
  if M.is_legacy_format(history) then
    return M.LEGACY_VERSION
  end
  
  return M.CURRENT_VERSION
end

--- 🔧 Creates migration metadata for tracking
---@param original_format string Original data format
---@param backup_path string | nil Path to backup file
---@return avante.MigrationMetadata metadata Migration tracking information
function M.create_migration_metadata(original_format, backup_path)
  return {
    version = M.CURRENT_VERSION,
    format = "unified",
    migrated_at = Utils.get_timestamp(),
    original_format = original_format,
    migration_uuid = Utils.uuid(),
    backup_path = backup_path,
  }
end

--- 💾 Creates atomic backup of original history file
---@param filepath Path Original history file path
---@return string | nil backup_path Path to backup file or nil if failed
function M.create_backup(filepath)
  if not filepath:exists() then
    Utils.warn("Cannot backup non-existent file: " .. tostring(filepath))
    return nil
  end
  
  local backup_path = Path:new(tostring(filepath) .. M.BACKUP_SUFFIX .. "_" .. os.time())
  
  local ok, err = pcall(function()
    filepath:copy({ destination = backup_path })
  end)
  
  if not ok then
    Utils.error("Failed to create backup: " .. (err or "unknown error"))
    return nil
  end
  
  Utils.debug("Created backup at: " .. tostring(backup_path))
  return tostring(backup_path)
end

--- ⚡ Atomically writes history to file using temporary file pattern
---@param filepath Path Target file path
---@param history avante.UnifiedChatHistory History data to write
---@return boolean success True if write succeeded
function M.atomic_write(filepath, history)
  local temp_path = Path:new(tostring(filepath) .. ".tmp." .. os.time())
  
  -- 📝 First write to temporary file
  local ok, err = pcall(function()
    local json_content = vim.json.encode(history)
    temp_path:write(json_content, "w")
  end)
  
  if not ok then
    Utils.error("Failed to write temporary file: " .. (err or "unknown error"))
    if temp_path:exists() then
      temp_path:rm()
    end
    return false
  end
  
  -- 🔄 Validate JSON before final move
  local validate_ok = pcall(function()
    local content = temp_path:read()
    vim.json.decode(content)
  end)
  
  if not validate_ok then
    Utils.error("JSON validation failed for migration data")
    temp_path:rm()
    return false
  end
  
  -- ⚡ Atomically replace original file
  local rename_ok, rename_err = pcall(function()
    if filepath:exists() then
      filepath:rm()
    end
    temp_path:rename({ new_name = tostring(filepath) })
  end)
  
  if not rename_ok then
    Utils.error("Failed to atomically replace file: " .. (rename_err or "unknown error"))
    if temp_path:exists() then
      temp_path:rm()
    end
    return false
  end
  
  Utils.debug("Atomically wrote history to: " .. tostring(filepath))
  return true
end

--- 🔄 Converts legacy ChatHistoryEntry to HistoryMessage format
---@param entry avante.ChatHistoryEntry Legacy history entry
---@return avante.HistoryMessage[] messages Converted messages
function M.convert_entry_to_messages(entry)
  local messages = {}
  
  -- 👤 Convert user request to HistoryMessage
  if entry.request and entry.request ~= "" then
    local user_message = Message:new("user", entry.request, {
      timestamp = entry.timestamp,
      is_user_submission = true,
      visible = entry.visible,
      selected_filepaths = entry.selected_filepaths,
      selected_code = entry.selected_code,
      provider = entry.provider,
      model = entry.model,
    })
    table.insert(messages, user_message)
  end
  
  -- 🤖 Convert assistant response to HistoryMessage
  if entry.response and entry.response ~= "" then
    local assistant_message = Message:new("assistant", entry.response, {
      timestamp = entry.timestamp,
      visible = entry.visible,
      provider = entry.provider,
      model = entry.model,
      original_content = entry.original_response and entry.original_response or nil,
    })
    table.insert(messages, assistant_message)
  end
  
  return messages
end

--- 🚀 Main migration function: converts legacy format to unified format
---@param history avante.ChatHistory Legacy history data
---@param backup_path string | nil Path to backup file
---@return avante.UnifiedChatHistory unified_history Migrated history data
function M.migrate_to_unified_format(history, backup_path)
  Utils.info("🔄 Starting migration from legacy format to unified format")
  
  ---@type avante.UnifiedChatHistory
  local unified_history = {
    title = history.title or "untitled",
    timestamp = history.timestamp,
    filename = history.filename,
    messages = {},
    todos = history.todos,
    memory = history.memory,
    system_prompt = history.system_prompt,
    tokens_usage = history.tokens_usage,
    version = M.CURRENT_VERSION,
    migration_metadata = M.create_migration_metadata("ChatHistoryEntry", backup_path),
  }
  
  -- 🔄 Convert all legacy entries to messages
  if history.entries then
    for _, entry in ipairs(history.entries) do
      local converted_messages = M.convert_entry_to_messages(entry)
      for _, message in ipairs(converted_messages) do
        table.insert(unified_history.messages, message)
      end
    end
    
    Utils.info(string.format("✅ Converted %d legacy entries to %d messages", 
                           #history.entries, #unified_history.messages))
  else
    Utils.debug("No entries found in legacy history")
  end
  
  -- 📋 Preserve existing messages if they exist (hybrid format)
  if history.messages then
    Utils.debug("Found existing messages, preserving them")
    for _, message in ipairs(history.messages) do
      table.insert(unified_history.messages, message)
    end
  end
  
  Utils.info("🎉 Migration to unified format completed successfully")
  return unified_history
end

--- 🔍 Validates migration integrity
---@param original avante.ChatHistory Original history data
---@param migrated avante.UnifiedChatHistory Migrated history data
---@return boolean valid True if migration is valid
---@return string | nil error Error message if validation fails
function M.validate_migration(original, migrated)
  -- ✅ Basic structure validation
  if not migrated.messages then
    return false, "Migrated history missing messages field"
  end
  
  if not migrated.migration_metadata then
    return false, "Migrated history missing migration metadata"
  end
  
  if migrated.version ~= M.CURRENT_VERSION then
    return false, "Migrated history has incorrect version"
  end
  
  -- 📊 Content preservation validation
  local expected_message_count = 0
  if original.entries then
    for _, entry in ipairs(original.entries) do
      if entry.request and entry.request ~= "" then
        expected_message_count = expected_message_count + 1
      end
      if entry.response and entry.response ~= "" then
        expected_message_count = expected_message_count + 1
      end
    end
  end
  
  if original.messages then
    expected_message_count = expected_message_count + #original.messages
  end
  
  if #migrated.messages ~= expected_message_count then
    return false, string.format("Message count mismatch: expected %d, got %d", 
                               expected_message_count, #migrated.messages)
  end
  
  Utils.debug("✅ Migration validation passed")
  return true, nil
end

--- 🛠️ Rollback migration using backup file
---@param filepath Path History file path
---@param backup_path string Backup file path
---@return boolean success True if rollback succeeded
function M.rollback_migration(filepath, backup_path)
  local backup_file = Path:new(backup_path)
  
  if not backup_file:exists() then
    Utils.error("Backup file not found for rollback: " .. backup_path)
    return false
  end
  
  local ok, err = pcall(function()
    backup_file:copy({ destination = filepath, override = true })
  end)
  
  if not ok then
    Utils.error("Failed to rollback migration: " .. (err or "unknown error"))
    return false
  end
  
  Utils.info("✅ Successfully rolled back migration using backup: " .. backup_path)
  return true
end

--- 📝 Logs migration activity
---@param bufnr integer Buffer number for context
---@param action string Action performed
---@param details string Additional details
function M.log_migration(bufnr, action, details)
  local History = require("avante.path").history
  local log_file = History.get_history_dir(bufnr):joinpath(M.MIGRATION_LOG_FILE)
  
  local log_entry = string.format("[%s] %s: %s\n", 
                                 Utils.get_timestamp(), action, details)
  
  local ok, err = pcall(function()
    log_file:write(log_entry, "a")
  end)
  
  if not ok then
    Utils.debug("Failed to write migration log: " .. (err or "unknown error"))
  end
end

return M
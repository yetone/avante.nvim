local Utils = require("avante.utils")
local Message = require("avante.history.message")
local Path = require("plenary.path")

---@class avante.history.MigrationEngine
local Migration = {}

---@class avante.migration.MigrationMetadata
---@field original_format "ChatHistoryEntry" | "HistoryMessage"
---@field migration_timestamp string
---@field tool_conversions_count integer
---@field legacy_entry_id? string
---@field conversion_warnings string[]

---Detects the format version of a history file
---@param raw_history table
---@return "ChatHistoryEntry" | "HistoryMessage" | "unknown"
function Migration.detect_format(raw_history)
  if raw_history.entries and not raw_history.messages then
    return "ChatHistoryEntry"
  elseif raw_history.messages and not raw_history.entries then
    return "HistoryMessage"
  elseif raw_history.version == "2.0" then
    return "HistoryMessage"
  else
    return "unknown"
  end
end

---Converts legacy ChatHistoryEntry format to unified HistoryMessage format
---@param legacy_history avante.ChatHistory
---@return avante.UnifiedChatHistory, string[] errors
function Migration.convert_legacy_format(legacy_history)
  local warnings = {}
  
  local unified = {
    version = "2.0",
    title = legacy_history.title or "untitled",
    timestamp = legacy_history.timestamp or Utils.get_timestamp(),
    messages = {},
    todos = legacy_history.todos,
    memory = legacy_history.memory,
    filename = legacy_history.filename,
    system_prompt = legacy_history.system_prompt,
    tokens_usage = legacy_history.tokens_usage,
    migration_metadata = {
      original_format = "ChatHistoryEntry",
      migration_timestamp = Utils.get_timestamp(),
      tool_conversions_count = 0,
      conversion_warnings = {}
    }
  }
  
  -- Convert legacy entries to HistoryMessage format
  for i, entry in ipairs(legacy_history.entries or {}) do
    local entry_id = "entry_" .. tostring(i)
    
    -- Convert user request
    if entry.request and entry.request ~= "" then
      local user_message = Message:new("user", entry.request, {
        timestamp = entry.timestamp or unified.timestamp,
        is_user_submission = true,
        visible = entry.visible ~= false, -- default to true if not specified
        selected_filepaths = entry.selected_filepaths,
        selected_code = entry.selected_code,
        uuid = entry.uuid or Utils.uuid(),
      })
      
      -- Add migration metadata to the message
      user_message.migration_metadata = {
        legacy_entry_id = entry_id,
        original_format = "ChatHistoryEntry"
      }
      
      table.insert(unified.messages, user_message)
    end
    
    -- Convert assistant response
    if entry.response and entry.response ~= "" then
      local assistant_message = Message:new("assistant", entry.response, {
        timestamp = entry.timestamp or unified.timestamp,
        visible = entry.visible ~= false, -- default to true if not specified
        provider = entry.provider,
        model = entry.model,
        uuid = entry.uuid or Utils.uuid(),
      })
      
      -- Add migration metadata to the message
      assistant_message.migration_metadata = {
        legacy_entry_id = entry_id,
        original_format = "ChatHistoryEntry"
      }
      
      table.insert(unified.messages, assistant_message)
    end
    
    -- Track any missing data that might indicate incomplete conversion
    if not entry.request and not entry.response then
      table.insert(warnings, "Empty entry found at index " .. i)
      table.insert(unified.migration_metadata.conversion_warnings, "Empty entry at " .. entry_id)
    end
  end
  
  unified.migration_metadata.tool_conversions_count = #unified.messages
  unified.migration_metadata.conversion_warnings = warnings
  
  return unified, warnings
end

---Validates the integrity of migrated data
---@param unified_history avante.UnifiedChatHistory
---@param original_history avante.ChatHistory
---@return boolean success, string[] errors
function Migration.validate_migration(unified_history, original_history)
  local errors = {}
  
  -- Check version
  if unified_history.version ~= "2.0" then
    table.insert(errors, "Invalid version: " .. tostring(unified_history.version))
  end
  
  -- Check basic fields preservation
  if unified_history.title ~= original_history.title then
    table.insert(errors, "Title mismatch during migration")
  end
  
  -- Count message pairs in original vs unified
  local original_entries_count = #(original_history.entries or {})
  local unified_messages_count = #(unified_history.messages or {})
  
  -- Each entry can produce 0-2 messages (request + response)
  if unified_messages_count == 0 and original_entries_count > 0 then
    table.insert(errors, "No messages converted from " .. original_entries_count .. " entries")
  end
  
  -- Validate message structure
  for i, message in ipairs(unified_history.messages or {}) do
    if not message.message or not message.message.role then
      table.insert(errors, "Invalid message structure at index " .. i)
    end
    
    if not message.uuid or not message.timestamp then
      table.insert(errors, "Missing required fields in message " .. i)
    end
  end
  
  return #errors == 0, errors
end

---Creates a backup of the original file before migration
---@param filepath Path
---@return Path backup_path, boolean success, string? error
function Migration.create_backup(filepath)
  local backup_path = Path:new(tostring(filepath) .. ".legacy_backup_" .. os.time())
  
  local success, error = pcall(function()
    filepath:copy({ destination = backup_path })
  end)
  
  return backup_path, success, error and tostring(error) or nil
end

---Performs atomic migration of a single history file
---@param filepath Path
---@return boolean success, string? error, boolean was_migrated
function Migration.migrate_file(filepath)
  if not filepath:exists() then
    return false, "File does not exist: " .. tostring(filepath), false
  end
  
  local content = filepath:read()
  if not content or content == "" then
    return false, "Could not read file or file is empty", false
  end
  
  local raw_history
  local parse_success, parse_error = pcall(function()
    raw_history = vim.json.decode(content)
  end)
  
  if not parse_success then
    return false, "Failed to parse JSON: " .. tostring(parse_error), false
  end
  
  local format = Migration.detect_format(raw_history)
  
  -- Already in unified format
  if format == "HistoryMessage" then
    return true, nil, false
  end
  
  -- Unknown format
  if format == "unknown" then
    return false, "Unknown or invalid history format", false
  end
  
  -- Create backup
  local backup_path, backup_success, backup_error = Migration.create_backup(filepath)
  if not backup_success then
    return false, "Failed to create backup: " .. tostring(backup_error), false
  end
  
  -- Convert to unified format
  local unified_history, conversion_warnings = Migration.convert_legacy_format(raw_history)
  
  -- Validate conversion
  local validation_success, validation_errors = Migration.validate_migration(unified_history, raw_history)
  if not validation_success then
    return false, "Migration validation failed: " .. table.concat(validation_errors, "; "), false
  end
  
  -- Write to temporary file first for atomic operation
  local temp_path = Path:new(tostring(filepath) .. ".tmp")
  local json_content = vim.json.encode(unified_history)
  
  local write_success, write_error = pcall(function()
    temp_path:write(json_content, "w")
  end)
  
  if not write_success then
    return false, "Failed to write temporary file: " .. tostring(write_error), false
  end
  
  -- Atomic move to final location
  local move_success, move_error = pcall(function()
    temp_path:rename(tostring(filepath))
  end)
  
  if not move_success then
    temp_path:rm() -- Cleanup
    return false, "Failed to move temporary file: " .. tostring(move_error), false
  end
  
  -- Log successful migration
  Utils.info("Successfully migrated " .. tostring(filepath) .. " from " .. format .. " to HistoryMessage format")
  
  if #conversion_warnings > 0 then
    Utils.warn("Migration warnings for " .. tostring(filepath) .. ": " .. table.concat(conversion_warnings, "; "))
  end
  
  return true, nil, true
end

---Scans for legacy format files in a project's history directory
---@param bufnr integer
---@return Path[] legacy_files
function Migration.detect_legacy_files(bufnr)
  local History = require("avante.path").history
  local history_dir = History.get_history_dir(bufnr)
  local legacy_files = {}
  
  if not history_dir:exists() then
    return legacy_files
  end
  
  local files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
  
  for _, file in ipairs(files) do
    if not file:match("metadata.json") then
      local filepath = Path:new(file)
      local content = filepath:read()
      
      if content and content ~= "" then
        local parse_success, raw_history = pcall(vim.json.decode, content)
        if parse_success and Migration.detect_format(raw_history) == "ChatHistoryEntry" then
          table.insert(legacy_files, filepath)
        end
      end
    end
  end
  
  return legacy_files
end

---Migrates all legacy files in a project
---@param bufnr integer
---@param progress_callback? fun(current: integer, total: integer, file: string)
---@return boolean success, table results
function Migration.migrate_project(bufnr, progress_callback)
  local legacy_files = Migration.detect_legacy_files(bufnr)
  local results = {
    total_files = #legacy_files,
    migrated_files = 0,
    failed_files = 0,
    errors = {}
  }
  
  if #legacy_files == 0 then
    Utils.info("No legacy files found for migration in buffer " .. bufnr)
    return true, results
  end
  
  Utils.info("Starting migration of " .. #legacy_files .. " files for buffer " .. bufnr)
  
  for i, filepath in ipairs(legacy_files) do
    if progress_callback then
      progress_callback(i, #legacy_files, tostring(filepath))
    end
    
    local success, error, was_migrated = Migration.migrate_file(filepath)
    
    if success and was_migrated then
      results.migrated_files = results.migrated_files + 1
    elseif not success then
      results.failed_files = results.failed_files + 1
      table.insert(results.errors, {
        file = tostring(filepath),
        error = error
      })
      Utils.error("Migration failed for " .. tostring(filepath) .. ": " .. tostring(error))
    end
  end
  
  local overall_success = results.failed_files == 0
  
  if overall_success then
    Utils.info("Migration completed successfully: " .. results.migrated_files .. " files migrated")
  else
    Utils.error("Migration completed with errors: " .. results.failed_files .. " failures out of " .. results.total_files .. " files")
  end
  
  return overall_success, results
end

---Restores from backup files (rollback functionality)
---@param bufnr integer
---@return boolean success, string? error
function Migration.rollback_migration(bufnr)
  local History = require("avante.path").history
  local history_dir = History.get_history_dir(bufnr)
  
  if not history_dir:exists() then
    return false, "History directory does not exist"
  end
  
  local backup_pattern = tostring(history_dir:joinpath("*.legacy_backup_*"))
  local backup_files = vim.fn.glob(backup_pattern, true, true)
  
  if #backup_files == 0 then
    return false, "No backup files found for rollback"
  end
  
  local restored_count = 0
  local errors = {}
  
  for _, backup_file in ipairs(backup_files) do
    local backup_path = Path:new(backup_file)
    local original_file = backup_file:gsub("%.legacy_backup_%d+$", "")
    local original_path = Path:new(original_file)
    
    local restore_success, restore_error = pcall(function()
      backup_path:copy({ destination = original_path })
      backup_path:rm() -- Remove backup after successful restore
    end)
    
    if restore_success then
      restored_count = restored_count + 1
      Utils.info("Restored " .. original_file .. " from backup")
    else
      table.insert(errors, {
        backup_file = backup_file,
        error = tostring(restore_error)
      })
      Utils.error("Failed to restore " .. original_file .. ": " .. tostring(restore_error))
    end
  end
  
  if #errors > 0 then
    return false, "Rollback completed with errors: " .. #errors .. " failures"
  end
  
  Utils.info("Rollback completed successfully: " .. restored_count .. " files restored")
  return true, nil
end

return Migration
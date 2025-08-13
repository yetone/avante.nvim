local Utils = require("avante.utils")
local Message = require("avante.history.message")
local Path = require("plenary.path")

---@class avante.history.MigrationEngine
local Migration = {}

---@class avante.UnifiedChatHistory
---@field version string Schema version for future migrations
---@field title string Conversation title
---@field timestamp string Last modified timestamp
---@field messages avante.HistoryMessage[] Unified message array
---@field todos avante.TODO[] | nil Task tracking
---@field memory avante.ChatMemory | nil Conversation memory
---@field filename string File identifier
---@field system_prompt string | nil Custom system prompt
---@field tokens_usage avante.LLMTokenUsage | nil Token consumption tracking
---@field migration_metadata table | nil Migration tracking information

---Detects if a history object uses legacy ChatHistoryEntry format
---@param history table Raw history data from JSON
---@return boolean is_legacy True if this is legacy format
---@return string format_type "legacy" | "modern" | "unified"
function Migration.detect_format(history)
  if history.version == "2.0" then
    return false, "unified"
  end
  
  if history.entries and not history.messages then
    return true, "legacy"
  end
  
  if history.messages and not history.entries then
    return false, "modern"
  end
  
  -- Both exist - hybrid state during migration
  if history.entries and history.messages then
    return true, "legacy" -- Treat as legacy for migration
  end
  
  return false, "modern"
end

---Converts legacy ChatHistoryEntry format to unified HistoryMessage format
---@param legacy_history avante.ChatHistory
---@return avante.UnifiedChatHistory unified_history, string[] errors
function Migration.convert_legacy_format(legacy_history)
  local errors = {}
  
  ---@type avante.UnifiedChatHistory
  local unified = {
    version = "2.0",
    title = legacy_history.title or "untitled",
    timestamp = legacy_history.timestamp or Utils.get_timestamp(),
    messages = {},
    todos = legacy_history.todos,
    memory = legacy_history.memory,
    filename = legacy_history.filename or "",
    system_prompt = legacy_history.system_prompt,
    tokens_usage = legacy_history.tokens_usage,
    migration_metadata = {
      original_format = "ChatHistoryEntry",
      migration_timestamp = Utils.get_timestamp(),
      original_entry_count = legacy_history.entries and #legacy_history.entries or 0,
      tool_conversions_count = 0
    }
  }
  
  -- Convert legacy entries to HistoryMessage format
  if legacy_history.entries then
    for i, entry in ipairs(legacy_history.entries) do
      -- Convert user request
      if entry.request and entry.request ~= "" then
        local user_message = Message:new("user", entry.request, {
          timestamp = entry.timestamp,
          is_user_submission = true,
          visible = entry.visible ~= false, -- Default to true if not specified
          selected_filepaths = entry.selected_filepaths,
          selected_code = entry.selected_code,
        })
        table.insert(unified.messages, user_message)
      end
      
      -- Convert assistant response
      if entry.response and entry.response ~= "" then
        local assistant_message = Message:new("assistant", entry.response, {
          timestamp = entry.timestamp,
          visible = entry.visible ~= false, -- Default to true if not specified
        })
        table.insert(unified.messages, assistant_message)
      end
      
      -- Track conversion progress
      if unified.migration_metadata then
        unified.migration_metadata.tool_conversions_count = 
          unified.migration_metadata.tool_conversions_count + 1
      end
    end
  end
  
  -- If there were already messages in modern format, merge them
  if legacy_history.messages then
    for _, message in ipairs(legacy_history.messages) do
      table.insert(unified.messages, message)
    end
  end
  
  return unified, errors
end

---Validates that a unified history object is properly structured
---@param unified_history avante.UnifiedChatHistory
---@return boolean is_valid, string[] validation_errors
function Migration.validate_unified_history(unified_history)
  local errors = {}
  
  if not unified_history.version then
    table.insert(errors, "Missing version field")
  elseif unified_history.version ~= "2.0" then
    table.insert(errors, "Invalid version: " .. tostring(unified_history.version))
  end
  
  if not unified_history.title then
    table.insert(errors, "Missing title field")
  end
  
  if not unified_history.timestamp then
    table.insert(errors, "Missing timestamp field")
  end
  
  if not unified_history.messages then
    table.insert(errors, "Missing messages array")
  elseif type(unified_history.messages) ~= "table" then
    table.insert(errors, "Messages field must be an array")
  end
  
  if not unified_history.filename then
    table.insert(errors, "Missing filename field")
  end
  
  return #errors == 0, errors
end

---Performs atomic migration of a single history file
---@param filepath Path Path to the history file
---@param backup_path Path | nil Optional backup path
---@return boolean success, string | nil error_message
function Migration.migrate_file(filepath, backup_path)
  if not filepath:exists() then
    return false, "File does not exist: " .. tostring(filepath)
  end
  
  local content = filepath:read()
  if not content then
    return false, "Could not read file: " .. tostring(filepath)
  end
  
  local ok, raw_history = pcall(vim.json.decode, content)
  if not ok then
    return false, "Invalid JSON in file: " .. tostring(filepath)
  end
  
  local is_legacy, format_type = Migration.detect_format(raw_history)
  if not is_legacy then
    return true, "File already in " .. format_type .. " format"
  end
  
  -- Create backup if requested
  if backup_path then
    local backup_ok, backup_err = pcall(function()
      filepath:copy({ destination = backup_path })
    end)
    if not backup_ok then
      return false, "Failed to create backup: " .. tostring(backup_err)
    end
  end
  
  -- Convert to unified format
  local unified_history, conversion_errors = Migration.convert_legacy_format(raw_history)
  if #conversion_errors > 0 then
    return false, "Conversion errors: " .. table.concat(conversion_errors, ", ")
  end
  
  -- Validate converted data
  local is_valid, validation_errors = Migration.validate_unified_history(unified_history)
  if not is_valid then
    return false, "Validation errors: " .. table.concat(validation_errors, ", ")
  end
  
  -- Write unified format atomically
  local temp_path = Path:new(tostring(filepath) .. ".tmp")
  local json_content = vim.json.encode(unified_history)
  
  -- Validate JSON serialization
  local parse_test = pcall(vim.json.decode, json_content)
  if not parse_test then
    return false, "JSON serialization validation failed"
  end
  
  -- Write to temporary file first
  local write_ok, write_err = pcall(function()
    temp_path:write(json_content, "w")
  end)
  
  if not write_ok then
    return false, "Failed to write temporary file: " .. tostring(write_err)
  end
  
  -- Atomic move to final location
  local move_ok, move_err = pcall(function()
    temp_path:rename(tostring(filepath))
  end)
  
  if not move_ok then
    temp_path:rm() -- Cleanup
    return false, "Failed to move temporary file: " .. tostring(move_err)
  end
  
  return true, nil
end

---Scans project directory for legacy format files
---@param bufnr integer Buffer number to get project path
---@return Path[] legacy_files List of files needing migration
function Migration.detect_legacy_files(bufnr)
  local history_path = require("avante.path").history
  local history_dir = history_path.get_history_dir(bufnr)
  
  if not history_dir:exists() then
    return {}
  end
  
  local pattern = tostring(history_dir:joinpath("*.json"))
  local files = vim.fn.glob(pattern, true, true)
  local legacy_files = {}
  
  for _, filepath_str in ipairs(files) do
    if not filepath_str:match("metadata%.json$") then
      local filepath = Path:new(filepath_str)
      local content = filepath:read()
      
      if content then
        local ok, raw_history = pcall(vim.json.decode, content)
        if ok then
          local is_legacy, _ = Migration.detect_format(raw_history)
          if is_legacy then
            table.insert(legacy_files, filepath)
          end
        end
      end
    end
  end
  
  return legacy_files
end

---Performs batch migration of all legacy files in a project
---@param bufnr integer Buffer number to get project path
---@param progress_callback function | nil Optional progress callback (index, total, filepath)
---@return table results Migration results with success/error counts and details
function Migration.batch_migrate(bufnr, progress_callback)
  local legacy_files = Migration.detect_legacy_files(bufnr)
  local results = {
    total_files = #legacy_files,
    successful_migrations = 0,
    failed_migrations = 0,
    errors = {},
    migrated_files = {}
  }
  
  for i, filepath in ipairs(legacy_files) do
    if progress_callback then
      progress_callback(i, #legacy_files, filepath)
    end
    
    -- Create backup path
    local backup_path = Path:new(tostring(filepath) .. ".legacy_backup")
    
    local success, error_msg = Migration.migrate_file(filepath, backup_path)
    if success then
      results.successful_migrations = results.successful_migrations + 1
      table.insert(results.migrated_files, tostring(filepath))
    else
      results.failed_migrations = results.failed_migrations + 1
      results.errors[tostring(filepath)] = error_msg
    end
  end
  
  return results
end

---Rollback a migrated file from its backup
---@param filepath Path Path to the current (migrated) file
---@param backup_path Path | nil Path to backup file (default: filepath + ".legacy_backup")
---@return boolean success, string | nil error_message
function Migration.rollback_migration(filepath, backup_path)
  backup_path = backup_path or Path:new(tostring(filepath) .. ".legacy_backup")
  
  if not backup_path:exists() then
    return false, "Backup file does not exist: " .. tostring(backup_path)
  end
  
  if not filepath:exists() then
    return false, "Current file does not exist: " .. tostring(filepath)
  end
  
  local rollback_ok, rollback_err = pcall(function()
    backup_path:copy({ destination = filepath })
  end)
  
  if not rollback_ok then
    return false, "Failed to restore from backup: " .. tostring(rollback_err)
  end
  
  return true, nil
end

---Get debug information about a history file
---@param filepath Path
---@return table debug_info
function Migration.get_debug_info(filepath)
  local debug_info = {
    exists = filepath:exists(),
    readable = false,
    valid_json = false,
    detected_format = "unknown",
    is_legacy = false,
    error_message = nil
  }
  
  if not debug_info.exists then
    debug_info.error_message = "File does not exist"
    return debug_info
  end
  
  local content = filepath:read()
  if not content then
    debug_info.error_message = "Could not read file"
    return debug_info
  end
  
  debug_info.readable = true
  
  local ok, raw_history = pcall(vim.json.decode, content)
  if not ok then
    debug_info.error_message = "Invalid JSON"
    return debug_info
  end
  
  debug_info.valid_json = true
  
  local is_legacy, format_type = Migration.detect_format(raw_history)
  debug_info.detected_format = format_type
  debug_info.is_legacy = is_legacy
  
  if is_legacy then
    local entry_count = raw_history.entries and #raw_history.entries or 0
    debug_info.legacy_entry_count = entry_count
  end
  
  return debug_info
end

return Migration
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

---Detects if a history file uses the legacy ChatHistoryEntry format
---@param history_data table
---@return boolean is_legacy
---@return string detected_format
function Migration.detect_legacy_format(history_data)
  if history_data.entries and not history_data.messages then
    return true, "ChatHistoryEntry"
  elseif history_data.messages and not history_data.entries then
    return false, "HistoryMessage"
  elseif history_data.entries and history_data.messages then
    return true, "Mixed" -- Mixed format, treat as legacy to ensure migration
  else
    return false, "Empty"
  end
end

---Validates the structure of legacy ChatHistoryEntry data
---@param entry avante.ChatHistoryEntry
---@return boolean is_valid
---@return string[] errors
local function validate_legacy_entry(entry)
  local errors = {}
  
  if not entry.timestamp then
    table.insert(errors, "Missing timestamp")
  end
  
  if not entry.request and not entry.response then
    table.insert(errors, "Entry has neither request nor response")
  end
  
  return #errors == 0, errors
end

---Converts a single legacy ChatHistoryEntry to HistoryMessage format
---@param entry avante.ChatHistoryEntry
---@return avante.HistoryMessage[] messages
---@return string[] errors
local function convert_legacy_entry_to_messages(entry)
  local messages = {}
  local errors = {}
  
  local is_valid, validation_errors = validate_legacy_entry(entry)
  if not is_valid then
    vim.list_extend(errors, validation_errors)
    return messages, errors
  end
  
  -- Convert request to user message
  if entry.request and entry.request ~= "" then
    local user_message = Message:new("user", entry.request, {
      timestamp = entry.timestamp,
      is_user_submission = true,
      visible = entry.visible ~= false, -- Default to true if not specified
      selected_filepaths = entry.selected_filepaths,
      selected_code = entry.selected_code,
    })
    table.insert(messages, user_message)
  end
  
  -- Convert response to assistant message
  if entry.response and entry.response ~= "" then
    local assistant_message = Message:new("assistant", entry.response, {
      timestamp = entry.timestamp,
      visible = entry.visible ~= false, -- Default to true if not specified
      provider = entry.provider,
      model = entry.model,
    })
    table.insert(messages, assistant_message)
  end
  
  return messages, errors
end

---Detects and converts legacy ChatHistoryEntry format to unified HistoryMessage format
---@param legacy_history avante.ChatHistory
---@return avante.UnifiedChatHistory unified_history
---@return string[] errors
function Migration.convert_legacy_format(legacy_history)
  local unified = {
    version = "2.0",
    title = legacy_history.title or "untitled",
    timestamp = legacy_history.timestamp or Utils.get_timestamp(),
    messages = {},
    filename = legacy_history.filename or "",
    todos = legacy_history.todos,
    memory = legacy_history.memory,
    system_prompt = legacy_history.system_prompt,
    tokens_usage = legacy_history.tokens_usage,
    migration_metadata = {
      original_format = "ChatHistoryEntry",
      migration_timestamp = Utils.get_timestamp(),
      tool_conversions_count = 0,
      legacy_entries_count = legacy_history.entries and #legacy_history.entries or 0,
    }
  }
  
  local all_errors = {}
  local tool_conversion_count = 0
  
  -- Convert legacy entries to HistoryMessage format
  if legacy_history.entries then
    for i, entry in ipairs(legacy_history.entries) do
      local messages, errors = convert_legacy_entry_to_messages(entry)
      
      if #errors > 0 then
        -- Prefix errors with entry index for easier debugging
        for _, error in ipairs(errors) do
          table.insert(all_errors, string.format("Entry %d: %s", i, error))
        end
      end
      
      -- Add converted messages even if there were some errors
      for _, message in ipairs(messages) do
        table.insert(unified.messages, message)
        
        -- Check if this message contains tool usage
        if message.tool_use_logs or message.tool_use_store then
          tool_conversion_count = tool_conversion_count + 1
        end
      end
    end
  end
  
  -- If we also have messages in the legacy format (mixed format), append them
  if legacy_history.messages then
    for _, message in ipairs(legacy_history.messages) do
      table.insert(unified.messages, message)
    end
  end
  
  unified.migration_metadata.tool_conversions_count = tool_conversion_count
  
  return unified, all_errors
end

---Creates a backup of the original file before migration
---@param filepath Path
---@return Path backup_path
---@return boolean success
---@return string? error
local function create_backup(filepath)
  local backup_path = Path:new(tostring(filepath) .. ".legacy_backup_" .. os.time())
  
  local success, error = pcall(function()
    filepath:copy({ destination = backup_path })
  end)
  
  if not success then
    return backup_path, false, "Failed to create backup: " .. tostring(error)
  end
  
  return backup_path, true, nil
end

---Validates that the migrated data maintains the same essential information
---@param original table
---@param migrated avante.UnifiedChatHistory
---@return boolean is_valid
---@return string[] issues
local function validate_migration_integrity(original, migrated)
  local issues = {}
  
  -- Check basic fields
  if original.title and original.title ~= migrated.title then
    table.insert(issues, "Title mismatch after migration")
  end
  
  if original.timestamp and original.timestamp ~= migrated.timestamp then
    table.insert(issues, "Timestamp mismatch after migration")
  end
  
  -- Check message count makes sense
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
  
  local actual_message_count = #migrated.messages
  if actual_message_count < expected_message_count then
    table.insert(issues, string.format(
      "Message count mismatch: expected at least %d, got %d",
      expected_message_count, actual_message_count
    ))
  end
  
  -- Validate version is set
  if migrated.version ~= "2.0" then
    table.insert(issues, "Version not set to 2.0")
  end
  
  -- Check migration metadata exists
  if not migrated.migration_metadata then
    table.insert(issues, "Migration metadata missing")
  end
  
  return #issues == 0, issues
end

---Migrates a single history file from legacy format to unified format
---@param filepath Path
---@return boolean success
---@return string[] errors
---@return string[] warnings
function Migration.migrate_file(filepath)
  local errors = {}
  local warnings = {}
  
  if not filepath:exists() then
    table.insert(errors, "File does not exist: " .. tostring(filepath))
    return false, errors, warnings
  end
  
  -- Read original content
  local content = filepath:read()
  if not content then
    table.insert(errors, "Could not read file: " .. tostring(filepath))
    return false, errors, warnings
  end
  
  -- Parse JSON
  local ok, original_data = pcall(vim.json.decode, content)
  if not ok then
    table.insert(errors, "Invalid JSON in file: " .. tostring(filepath))
    return false, errors, warnings
  end
  
  -- Check if migration is needed
  local is_legacy, detected_format = Migration.detect_legacy_format(original_data)
  if not is_legacy then
    table.insert(warnings, "File is already in unified format: " .. detected_format)
    return true, errors, warnings
  end
  
  Utils.info("Migrating legacy format (" .. detected_format .. "): " .. tostring(filepath))
  
  -- Create backup
  local backup_path, backup_success, backup_error = create_backup(filepath)
  if not backup_success then
    table.insert(errors, backup_error)
    return false, errors, warnings
  end
  
  -- Convert to unified format
  local unified_history, conversion_errors = Migration.convert_legacy_format(original_data)
  
  if #conversion_errors > 0 then
    for _, error in ipairs(conversion_errors) do
      table.insert(warnings, "Conversion warning: " .. error)
    end
  end
  
  -- Validate migration integrity
  local is_valid, validation_issues = validate_migration_integrity(original_data, unified_history)
  if not is_valid then
    for _, issue in ipairs(validation_issues) do
      table.insert(errors, "Migration integrity issue: " .. issue)
    end
    return false, errors, warnings
  end
  
  -- Write unified format
  local json_content = vim.json.encode(unified_history)
  local write_success, write_error = pcall(function()
    filepath:write(json_content, "w")
  end)
  
  if not write_success then
    table.insert(errors, "Failed to write migrated file: " .. tostring(write_error))
    -- Attempt to restore backup
    pcall(function()
      backup_path:copy({ destination = filepath })
    end)
    return false, errors, warnings
  end
  
  Utils.info("Migration completed: " .. tostring(filepath))
  table.insert(warnings, "Backup created: " .. tostring(backup_path))
  
  return true, errors, warnings
end

---Scans a directory for history files that need migration
---@param history_dir Path
---@return Path[] legacy_files
---@return table migration_stats
function Migration.scan_for_legacy_files(history_dir)
  local legacy_files = {}
  local stats = {
    total_files = 0,
    legacy_files = 0,
    unified_files = 0,
    corrupted_files = 0,
  }
  
  if not history_dir:exists() then
    return legacy_files, stats
  end
  
  local pattern = tostring(history_dir:joinpath("*.json"))
  local files = vim.fn.glob(pattern, true, true)
  
  for _, filename in ipairs(files) do
    -- Skip metadata files
    if not filename:match("metadata%.json") and not filename:match("%.legacy_backup_") then
      stats.total_files = stats.total_files + 1
      local filepath = Path:new(filename)
      
      local content = filepath:read()
      if content then
        local ok, data = pcall(vim.json.decode, content)
        if ok then
          local is_legacy, _ = Migration.detect_legacy_format(data)
          if is_legacy then
            table.insert(legacy_files, filepath)
            stats.legacy_files = stats.legacy_files + 1
          else
            stats.unified_files = stats.unified_files + 1
          end
        else
          stats.corrupted_files = stats.corrupted_files + 1
        end
      else
        stats.corrupted_files = stats.corrupted_files + 1
      end
    end
  end
  
  return legacy_files, stats
end

---Migrates all legacy files in a project's history directory
---@param bufnr integer
---@param progress_callback? fun(current: integer, total: integer, filepath: Path)
---@return boolean success
---@return table migration_report
function Migration.migrate_project(bufnr, progress_callback)
  local History = require("avante.path").history
  local history_dir = History.get_history_dir(bufnr)
  
  local legacy_files, initial_stats = Migration.scan_for_legacy_files(history_dir)
  
  local report = {
    initial_stats = initial_stats,
    migrated_files = 0,
    failed_files = 0,
    total_errors = {},
    total_warnings = {},
    migration_start = Utils.get_timestamp(),
    migration_end = nil,
  }
  
  if #legacy_files == 0 then
    Utils.info("No legacy files found for migration")
    report.migration_end = Utils.get_timestamp()
    return true, report
  end
  
  Utils.info(string.format("Starting migration of %d legacy files", #legacy_files))
  
  for i, filepath in ipairs(legacy_files) do
    if progress_callback then
      progress_callback(i, #legacy_files, filepath)
    end
    
    local success, errors, warnings = Migration.migrate_file(filepath)
    
    if success then
      report.migrated_files = report.migrated_files + 1
    else
      report.failed_files = report.failed_files + 1
    end
    
    -- Collect all errors and warnings
    vim.list_extend(report.total_errors, errors)
    vim.list_extend(report.total_warnings, warnings)
  end
  
  report.migration_end = Utils.get_timestamp()
  
  local overall_success = report.failed_files == 0
  
  if overall_success then
    Utils.info(string.format("Migration completed successfully: %d files migrated", report.migrated_files))
  else
    Utils.warn(string.format(
      "Migration completed with issues: %d successful, %d failed",
      report.migrated_files, report.failed_files
    ))
  end
  
  return overall_success, report
end

---Gets debug information about a potentially problematic file
---@param filepath Path
---@return table debug_info
function Migration.get_debug_info(filepath)
  local debug_info = {
    file_exists = filepath:exists(),
    file_size = nil,
    detected_format = "unknown",
    json_valid = false,
    content_sample = nil,
    errors = {},
  }
  
  if not debug_info.file_exists then
    table.insert(debug_info.errors, "File does not exist")
    return debug_info
  end
  
  debug_info.file_size = filepath:stat().size
  
  local content = filepath:read()
  if not content then
    table.insert(debug_info.errors, "Could not read file")
    return debug_info
  end
  
  debug_info.content_sample = string.sub(content, 1, 200) .. (string.len(content) > 200 and "..." or "")
  
  local ok, data = pcall(vim.json.decode, content)
  debug_info.json_valid = ok
  
  if not ok then
    table.insert(debug_info.errors, "Invalid JSON: " .. tostring(data))
    return debug_info
  end
  
  local is_legacy, format = Migration.detect_legacy_format(data)
  debug_info.detected_format = format
  debug_info.is_legacy = is_legacy
  
  if is_legacy and data.entries then
    debug_info.entries_count = #data.entries
  end
  if data.messages then
    debug_info.messages_count = #data.messages
  end
  
  return debug_info
end

return Migration
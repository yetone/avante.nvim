local Utils = require("avante.utils")
local Message = require("avante.history.message")
local Path = require("plenary.path")

---@class avante.HistoryMigration
local M = {}

---@enum avante.HistoryFormat
M.FORMAT = {
  LEGACY = "legacy",
  UNIFIED = "unified",
}

---@class avante.MigrationMetadata
---@field version string
---@field migrated_at string
---@field original_format avante.HistoryFormat
---@field backup_file string | nil

---@class avante.UnifiedChatHistory : avante.ChatHistory
---@field version string
---@field migration_metadata avante.MigrationMetadata | nil

-- 🔄 Constants for migration versioning
M.CURRENT_VERSION = "1.0.0"
M.BACKUP_SUFFIX = ".backup"

---🔍 Detects the format of a chat history object
---@param history avante.ChatHistory
---@return avante.HistoryFormat
function M.detect_format(history)
  -- 🎯 Legacy format has 'entries' field, unified format has 'messages' field
  if history.entries and not history.messages then
    return M.FORMAT.LEGACY
  elseif history.messages and not history.entries then
    return M.FORMAT.UNIFIED
  elseif history.entries and history.messages then
    -- 🔄 Dual format exists, prioritize messages if present and populated
    return #history.messages > 0 and M.FORMAT.UNIFIED or M.FORMAT.LEGACY
  else
    -- 🆕 Empty history defaults to unified format
    return M.FORMAT.UNIFIED
  end
end

---🔄 Converts legacy ChatHistoryEntry array to HistoryMessage array with enhanced tool processing preservation
---@param entries avante.ChatHistoryEntry[]
---@param preserve_metadata? boolean
---@return avante.HistoryMessage[]
function M.convert_entries_to_messages(entries, preserve_metadata)
  local messages = {}
  
  for _, entry in ipairs(entries or {}) do
    -- 👤 Create user message from request
    if entry.request and entry.request ~= "" then
      local user_opts = {
        timestamp = entry.timestamp,
        is_user_submission = true,
        visible = entry.visible,
        selected_filepaths = entry.selected_filepaths,
        selected_code = entry.selected_code,
      }
      
      -- 📝 Preserve additional metadata if requested
      if preserve_metadata then
        user_opts.provider = entry.provider
        user_opts.model = entry.model
      end
      
      local user_message = Message:new("user", entry.request, user_opts)
      table.insert(messages, user_message)
    end
    
    -- 🤖 Create assistant message from response
    if entry.response and entry.response ~= "" then
      local assistant_opts = {
        timestamp = entry.timestamp,
        visible = entry.visible,
      }
      
      -- 📝 Preserve additional metadata if requested  
      if preserve_metadata then
        assistant_opts.provider = entry.provider
        assistant_opts.model = entry.model
        -- 🔄 Store original_response if different from response
        if entry.original_response and entry.original_response ~= entry.response then
          assistant_opts.original_content = entry.original_response
        end
      end
      
      local assistant_message = Message:new("assistant", entry.response, assistant_opts)
      table.insert(messages, assistant_message)
    end
  end
  
  -- 🔧 Apply tool processing preservation enhancements
  return M.enhance_tool_processing_continuity(messages)
end

---🔧 Enhances tool processing continuity for migrated messages
---@param messages avante.HistoryMessage[]
---@return avante.HistoryMessage[]
function M.enhance_tool_processing_continuity(messages)
  -- 🔍 Analyze messages for potential tool interactions
  local enhanced_messages = {}
  
  for i, message in ipairs(messages) do
    table.insert(enhanced_messages, message)
    
    -- 🔍 Look for patterns that might indicate tool interactions
    local content = message.message.content
    local content_text = type(content) == "string" and content or 
                        (type(content) == "table" and content[1] and 
                         type(content[1]) == "string" and content[1] or 
                         (content[1].type == "text" and content[1].text or ""))
    
    -- 🔍 Detect potential tool invocations that might need synthetic messages
    if message.message.role == "assistant" and content_text then
      -- 🔍 Look for file edit patterns that might need follow-up view messages
      local file_edit_patterns = {
        "edited.*%.%w+",
        "modified.*%.%w+", 
        "updated.*%.%w+",
        "created.*%.%w+",
        "changed.*%.%w+"
      }
      
      for _, pattern in ipairs(file_edit_patterns) do
        if content_text:match(pattern) then
          -- 📝 This might benefit from synthetic follow-up messages
          -- 🔧 Mark for potential tool chain optimization in collect_tool_info
          message.is_migrated_edit_candidate = true
          break
        end
      end
    end
  end
  
  return enhanced_messages
end

---💾 Creates atomic backup of original file before migration
---@param filepath Path
---@return string backup_path
---@return string | nil error
function M.create_backup(filepath)
  local backup_path = tostring(filepath) .. M.BACKUP_SUFFIX
  local backup_filepath = Path:new(backup_path)
  
  -- 🛡️ Ensure backup doesn't already exist
  if backup_filepath:exists() then
    return backup_path, "Backup file already exists: " .. backup_path
  end
  
  -- 📋 Copy original to backup location
  local success = pcall(function()
    filepath:copy({ destination = backup_filepath })
  end)
  
  if not success then
    return backup_path, "Failed to create backup at: " .. backup_path
  end
  
  return backup_path, nil
end

---♻️ Restores from backup and removes backup file
---@param filepath Path
---@param backup_path string
---@return boolean success
---@return string | nil error
function M.restore_from_backup(filepath, backup_path)
  local backup_filepath = Path:new(backup_path)
  
  if not backup_filepath:exists() then
    return false, "Backup file not found: " .. backup_path
  end
  
  -- 🔄 Copy backup back to original location
  local success, err = pcall(function()
    backup_filepath:copy({ destination = filepath, override = true })
    backup_filepath:rm() -- 🗑️ Clean up backup after successful restore
  end)
  
  if not success then
    return false, "Failed to restore from backup: " .. tostring(err)
  end
  
  return true, nil
end

---⚡ Atomically writes data to file using temporary file and rename
---@param filepath Path
---@param data string
---@return boolean success
---@return string | nil error
function M.atomic_write(filepath, data)
  local temp_path = tostring(filepath) .. ".tmp"
  local temp_filepath = Path:new(temp_path)
  
  -- 📝 Write to temporary file first
  local write_success, write_err = pcall(function()
    temp_filepath:write(data, "w")
  end)
  
  if not write_success then
    -- 🧹 Clean up temp file on failure
    if temp_filepath:exists() then
      temp_filepath:rm()
    end
    return false, "Failed to write temporary file: " .. tostring(write_err)
  end
  
  -- 🔄 Atomic rename to final location
  local rename_success = pcall(function()
    temp_filepath:rename({ new_name = tostring(filepath) })
  end)
  
  if not rename_success then
    -- 🧹 Clean up temp file on failure
    if temp_filepath:exists() then
      temp_filepath:rm()
    end
    return false, "Failed to rename temporary file to final location"
  end
  
  return true, nil
end

---✅ Validates migrated data structure
---@param history avante.UnifiedChatHistory
---@return boolean valid
---@return string | nil error
function M.validate_migrated_history(history)
  -- 🔍 Check required fields
  if not history.messages then
    return false, "Missing messages field in migrated history"
  end
  
  if not history.version then
    return false, "Missing version field in migrated history"
  end
  
  -- 🔍 Validate messages structure
  for i, message in ipairs(history.messages) do
    if not message.message then
      return false, string.format("Message %d missing message field", i)
    end
    
    if not message.message.role then
      return false, string.format("Message %d missing role field", i)
    end
    
    if not message.message.content then
      return false, string.format("Message %d missing content field", i)
    end
    
    if not message.timestamp then
      return false, string.format("Message %d missing timestamp field", i)
    end
  end
  
  return true, nil
end

---🚀 Main migration function - converts legacy format to unified format
---@param history avante.ChatHistory
---@param filepath Path | nil
---@return avante.UnifiedChatHistory | nil
---@return string | nil error
function M.migrate_to_unified(history, filepath)
  local format = M.detect_format(history)
  
  -- ✅ Already in unified format
  if format == M.FORMAT.UNIFIED then
    -- 🔄 Ensure version is set
    if not history.version then
      history.version = M.CURRENT_VERSION
    end
    return history, nil
  end
  
  -- 🔄 Convert from legacy format
  local migrated_messages = M.convert_entries_to_messages(history.entries, true)
  
  -- 🏗️ Build unified history structure
  ---@type avante.UnifiedChatHistory
  local unified_history = {
    title = history.title or "untitled",
    timestamp = history.timestamp or Utils.get_timestamp(),
    messages = migrated_messages,
    todos = history.todos,
    memory = history.memory,
    filename = history.filename,
    system_prompt = history.system_prompt,
    tokens_usage = history.tokens_usage,
    version = M.CURRENT_VERSION,
    migration_metadata = {
      version = M.CURRENT_VERSION,
      migrated_at = Utils.get_timestamp(),
      original_format = M.FORMAT.LEGACY,
      backup_file = filepath and (tostring(filepath) .. M.BACKUP_SUFFIX) or nil,
    },
  }
  
  -- ✅ Validate the migrated structure
  local valid, validation_error = M.validate_migrated_history(unified_history)
  if not valid then
    return nil, "Migration validation failed: " .. (validation_error or "unknown error")
  end
  
  return unified_history, nil
end

---🔄 Full migration workflow with backup and atomic operations
---@param filepath Path
---@return boolean success
---@return string | nil error
---@return avante.UnifiedChatHistory | nil migrated_history
function M.migrate_file(filepath)
  if not filepath:exists() then
    return false, "File does not exist: " .. tostring(filepath), nil
  end
  
  -- 📖 Read original file
  local content = filepath:read()
  if not content then
    return false, "Failed to read file: " .. tostring(filepath), nil
  end
  
  -- 🔍 Parse JSON
  local history
  local parse_success, parse_err = pcall(function()
    history = vim.json.decode(content)
  end)
  
  if not parse_success then
    return false, "Failed to parse JSON: " .. tostring(parse_err), nil
  end
  
  -- 🔍 Check if migration is needed
  local format = M.detect_format(history)
  if format == M.FORMAT.UNIFIED then
    return true, "File already in unified format", history
  end
  
  -- 💾 Create backup
  local backup_path, backup_err = M.create_backup(filepath)
  if backup_err then
    return false, backup_err, nil
  end
  
  -- 🔄 Perform migration
  local migrated_history, migration_err = M.migrate_to_unified(history, filepath)
  if migration_err then
    -- 🔙 Restore from backup on migration failure
    M.restore_from_backup(filepath, backup_path)
    return false, migration_err, nil
  end
  
  -- 💾 Atomically save migrated data
  local json_data = vim.json.encode(migrated_history)
  local write_success, write_err = M.atomic_write(filepath, json_data)
  
  if not write_success then
    -- 🔙 Restore from backup on write failure
    M.restore_from_backup(filepath, backup_path)
    return false, write_err, nil
  end
  
  return true, nil, migrated_history
end

---📊 Migration progress reporting
---@param current integer
---@param total integer
---@param filename string | nil
function M.report_progress(current, total, filename)
  local percentage = math.floor((current / total) * 100)
  local message = string.format("🔄 Migration progress: %d/%d (%d%%)", current, total, percentage)
  
  if filename then
    message = message .. " - " .. filename
  end
  
  Utils.info(message)
end

---🗑️ Cleanup backup files after successful migration
---@param backup_path string
function M.cleanup_backup(backup_path)
  local backup_filepath = Path:new(backup_path)
  if backup_filepath:exists() then
    backup_filepath:rm()
  end
end

---📦 Batch migration functionality for multiple projects
---@param projects_dir Path
---@param options? { dry_run?: boolean, cleanup_backups?: boolean, max_concurrent?: integer }
---@return { success: integer, failed: integer, total: integer, errors: string[] }
function M.migrate_all_projects(projects_dir, options)
  options = options or {}
  local dry_run = options.dry_run or false
  local cleanup_backups = options.cleanup_backups or false
  local max_concurrent = options.max_concurrent or 5
  
  local results = {
    success = 0,
    failed = 0,
    total = 0,
    errors = {}
  }
  
  if not projects_dir:exists() then
    table.insert(results.errors, "Projects directory does not exist: " .. tostring(projects_dir))
    return results
  end
  
  -- 🔍 Find all history directories
  local Scan = require("plenary.scandir")
  local history_dirs = Scan.scan_dir(tostring(projects_dir), {
    depth = 2,
    only_dirs = true,
    search_pattern = "history$"
  })
  
  Utils.info("🔍 Found " .. #history_dirs .. " history directories to process")
  
  for _, history_dir in ipairs(history_dirs) do
    local history_path = Path:new(history_dir)
    local json_files = vim.fn.glob(tostring(history_path:joinpath("*.json")), true, true)
    
    for _, json_file in ipairs(json_files) do
      if not json_file:match("metadata.json") then
        results.total = results.total + 1
        local filepath = Path:new(json_file)
        
        M.report_progress(results.total, #json_files * #history_dirs, filepath:basename())
        
        if not dry_run then
          local success, error_msg = M.migrate_file(filepath)
          if success then
            results.success = results.success + 1
            -- 🗑️ Cleanup backup if requested
            if cleanup_backups and error_msg then
              local backup_path = tostring(filepath) .. M.BACKUP_SUFFIX
              M.cleanup_backup(backup_path)
            end
          else
            results.failed = results.failed + 1
            table.insert(results.errors, filepath:basename() .. ": " .. (error_msg or "unknown error"))
          end
        end
      end
    end
  end
  
  return results
end

---🔧 Manual migration trigger for specific file
---@param filepath string | Path
---@return boolean success
---@return string | nil error
function M.manual_migrate(filepath)
  local file_path = type(filepath) == "string" and Path:new(filepath) or filepath
  
  if not file_path:exists() then
    return false, "File does not exist: " .. tostring(file_path)
  end
  
  Utils.info("🔄 Manually triggering migration for: " .. file_path:basename())
  
  local success, error_msg, migrated_history = M.migrate_file(file_path)
  
  if success then
    Utils.info("✅ Manual migration completed successfully")
    return true, nil
  else
    Utils.warn("❌ Manual migration failed: " .. (error_msg or "unknown error"))
    return false, error_msg
  end
end

---📈 Migration status and statistics
---@param projects_dir Path
---@return { legacy_files: integer, unified_files: integer, needs_migration: string[] }
function M.get_migration_status(projects_dir)
  local status = {
    legacy_files = 0,
    unified_files = 0,
    needs_migration = {}
  }
  
  if not projects_dir:exists() then
    return status
  end
  
  local Scan = require("plenary.scandir")
  local history_dirs = Scan.scan_dir(tostring(projects_dir), {
    depth = 2,
    only_dirs = true,
    search_pattern = "history$"
  })
  
  for _, history_dir in ipairs(history_dirs) do
    local history_path = Path:new(history_dir)
    local json_files = vim.fn.glob(tostring(history_path:joinpath("*.json")), true, true)
    
    for _, json_file in ipairs(json_files) do
      if not json_file:match("metadata.json") then
        local filepath = Path:new(json_file)
        local content = filepath:read()
        
        if content then
          local parse_success, history = pcall(function()
            return vim.json.decode(content)
          end)
          
          if parse_success then
            local format = M.detect_format(history)
            if format == M.FORMAT.LEGACY then
              status.legacy_files = status.legacy_files + 1
              table.insert(status.needs_migration, json_file)
            else
              status.unified_files = status.unified_files + 1
            end
          end
        end
      end
    end
  end
  
  return status
end

return M
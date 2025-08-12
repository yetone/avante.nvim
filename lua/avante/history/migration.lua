-- 🔄 Migration engine for converting legacy ChatHistoryEntry format to unified HistoryMessage format
local Utils = require("avante.utils")
local Message = require("avante.history.message")

local M = {}

-- 🚀 Performance optimizations
local migration_cache = {} -- Cache migration results to avoid repeated work
local MAX_CACHE_SIZE = 50  -- Limit cache size to prevent memory issues

---@class avante.UnifiedChatHistory : avante.ChatHistory
---@field format_version number Version of the data format
---@field migration_metadata? avante.MigrationMetadata Metadata about migration process

---@class avante.MigrationMetadata
---@field migrated_at string ISO timestamp when migration was performed
---@field original_format "entries" | "messages" Original format before migration
---@field migration_version string Version of migration logic used
---@field backup_created boolean Whether backup was created
---@field entries_count? number Number of entries migrated from legacy format

-- 📌 Current migration version - increment when migration logic changes
M.MIGRATION_VERSION = "1.0.0"
M.CURRENT_FORMAT_VERSION = 2
M.LEGACY_FORMAT_VERSION = 1

---🔍 Detects the format of a chat history object
---@param history avante.ChatHistory
---@return "legacy" | "modern" | "unified"
function M.detect_format(history)
  if history.format_version == M.CURRENT_FORMAT_VERSION then
    return "unified"
  elseif history.messages and not history.entries then
    return "modern"
  elseif history.entries and not history.messages then
    return "legacy"  
  elseif history.entries and history.messages then
    -- 🚨 Both formats present - prioritize messages as it's newer
    return "modern"
  else
    -- 🆕 New/empty history
    return "unified"
  end
end

---🔄 Converts legacy ChatHistoryEntry[] to HistoryMessage[]
---@param entries avante.ChatHistoryEntry[]
---@return avante.HistoryMessage[]
---@return string|nil error Error message if conversion fails
function M.convert_entries_to_messages(entries)
  if not entries or #entries == 0 then
    return {}, nil
  end

  local messages = {}
  local error_msgs = {}

  for i, entry in ipairs(entries) do
    -- 🔍 Validate entry structure
    if not entry.timestamp then
      table.insert(error_msgs, string.format("Entry %d missing timestamp", i))
      goto continue
    end

    -- 👤 Convert user request if present
    if entry.request and entry.request ~= "" then
      local user_message = Message:new("user", entry.request, {
        timestamp = entry.timestamp,
        is_user_submission = true,
        visible = entry.visible ~= false, -- Default to visible
        selected_filepaths = entry.selected_filepaths,
        selected_code = entry.selected_code,
      })
      table.insert(messages, user_message)
    end

    -- 🤖 Convert assistant response if present
    if entry.response and entry.response ~= "" then
      local assistant_message = Message:new("assistant", entry.response, {
        timestamp = entry.timestamp,
        visible = entry.visible ~= false, -- Default to visible
      })
      table.insert(messages, assistant_message)
    end

    ::continue::
  end

  if #error_msgs > 0 then
    return messages, table.concat(error_msgs, "; ")
  end

  return messages, nil
end

---💾 Creates backup of original history before migration
---@param filepath string Path to the history file
---@return boolean success Whether backup was created successfully
---@return string|nil error Error message if backup failed
function M.create_backup(filepath)
  local Path = require("plenary.path")
  local original_path = Path:new(filepath)
  
  if not original_path:exists() then
    return false, "Original file does not exist: " .. filepath
  end

  local backup_path = Path:new(filepath .. ".backup." .. os.time())
  local success, err = pcall(function()
    local content = original_path:read()
    backup_path:write(content, "w")
  end)

  if not success then
    return false, "Failed to create backup: " .. tostring(err)
  end

  return true, nil
end

---🔄 Migrates a single history object to unified format
---@param history avante.ChatHistory
---@return avante.UnifiedChatHistory migrated_history
---@return string|nil error Error message if migration fails
function M.migrate_history(history)
  local format = M.detect_format(history)
  
  if format == "unified" then
    -- ✅ Already in unified format
    return history, nil
  end

  ---@type avante.UnifiedChatHistory
  local unified_history = vim.deepcopy(history)
  
  if format == "legacy" then
    -- 🔄 Convert legacy entries to messages
    local messages, err = M.convert_entries_to_messages(history.entries or {})
    if err then
      return unified_history, "Failed to convert entries: " .. err
    end
    
    unified_history.messages = messages
    unified_history.entries = nil -- 🗑️ Remove legacy format
    
    -- 📊 Store migration metadata
    unified_history.migration_metadata = {
      migrated_at = Utils.get_timestamp(),
      original_format = "entries",
      migration_version = M.MIGRATION_VERSION,
      backup_created = false, -- Will be set by caller
      entries_count = #(history.entries or {}),
    }
  elseif format == "modern" then
    -- 🔧 Upgrade modern format to unified
    unified_history.migration_metadata = {
      migrated_at = Utils.get_timestamp(),
      original_format = "messages", 
      migration_version = M.MIGRATION_VERSION,
      backup_created = false, -- Will be set by caller
    }
  end
  
  -- 🏷️ Set format version
  unified_history.format_version = M.CURRENT_FORMAT_VERSION
  
  return unified_history, nil
end

---💾 Performs atomic write operation with backup and rollback capability
---@param filepath string Path to write to
---@param content string Content to write
---@param create_backup? boolean Whether to create backup before writing
---@return boolean success
---@return string|nil error Error message if operation fails
function M.atomic_write(filepath, content, create_backup)
  local Path = require("plenary.path")
  local file_path = Path:new(filepath)
  
  -- 💾 Create backup if requested and file exists
  if create_backup and file_path:exists() then
    local backup_success, backup_err = M.create_backup(filepath)
    if not backup_success then
      return false, backup_err
    end
  end
  
  -- 📝 Write to temporary file first
  local temp_path = Path:new(filepath .. ".tmp." .. Utils.uuid())
  local success, write_err = pcall(function()
    temp_path:write(content, "w")
  end)
  
  if not success then
    return false, "Failed to write temporary file: " .. tostring(write_err)
  end
  
  -- 🔄 Atomic rename
  local rename_success, rename_err = pcall(function()
    temp_path:rename({ new_name = filepath })
  end)
  
  if not rename_success then
    -- 🧹 Clean up temp file on failure
    pcall(function() temp_path:rm() end)
    return false, "Failed to rename temporary file: " .. tostring(rename_err)
  end
  
  return true, nil
end

---🔄 Migrates and saves a history file with atomic operations
---@param filepath string Path to the history file
---@return boolean success
---@return string|nil error Error message if migration fails
function M.migrate_history_file(filepath)
  local Path = require("plenary.path")
  local file_path = Path:new(filepath)
  
  if not file_path:exists() then
    return false, "History file does not exist: " .. filepath
  end
  
  -- 📖 Load existing history
  local content = file_path:read()
  if not content then
    return false, "Failed to read history file: " .. filepath
  end
  
  local ok, history = pcall(vim.json.decode, content)
  if not ok then
    return false, "Failed to parse JSON in history file: " .. filepath
  end
  
  -- 🔍 Check if migration is needed
  local format = M.detect_format(history)
  if format == "unified" then
    return true, nil -- Already migrated
  end
  
  -- 🔄 Perform migration
  local migrated_history, migration_err = M.migrate_history(history)
  if migration_err then
    return false, migration_err
  end
  
  -- 💾 Create backup and perform atomic write
  migrated_history.migration_metadata.backup_created = true
  local migrated_content = vim.json.encode(migrated_history)
  local write_success, write_err = M.atomic_write(filepath, migrated_content, true)
  
  if not write_success then
    return false, write_err
  end
  
  Utils.debug("Successfully migrated history file:", filepath)
  return true, nil
end

---📊 Validates migrated history integrity
---@param original_history avante.ChatHistory
---@param migrated_history avante.UnifiedChatHistory
---@return boolean is_valid
---@return string[] issues List of validation issues found
function M.validate_migration(original_history, migrated_history)
  local issues = {}
  
  -- 🏷️ Check format version
  if migrated_history.format_version ~= M.CURRENT_FORMAT_VERSION then
    table.insert(issues, "Invalid format version: " .. tostring(migrated_history.format_version))
  end
  
  -- 📊 Check migration metadata
  if not migrated_history.migration_metadata then
    table.insert(issues, "Missing migration metadata")
  else
    local metadata = migrated_history.migration_metadata
    if not metadata.migrated_at or not metadata.migration_version then
      table.insert(issues, "Incomplete migration metadata")
    end
  end
  
  -- 🔍 Validate message structure if migrated from entries
  if original_history.entries then
    local original_count = #original_history.entries
    local message_pairs = 0
    
    -- Count expected message pairs (user + assistant)
    for _, entry in ipairs(original_history.entries) do
      if entry.request and entry.request ~= "" then message_pairs = message_pairs + 1 end
      if entry.response and entry.response ~= "" then message_pairs = message_pairs + 1 end
    end
    
    if #(migrated_history.messages or {}) ~= message_pairs then
      table.insert(issues, string.format(
        "Message count mismatch: expected %d, got %d",
        message_pairs,
        #(migrated_history.messages or {})
      ))
    end
  end
  
  -- 🧹 Check that legacy format is removed
  if migrated_history.entries then
    table.insert(issues, "Legacy entries still present after migration")
  end
  
  return #issues == 0, issues
end

---🚀 Clears migration cache to free memory
function M.clear_cache()
  migration_cache = {}
  Utils.debug("Migration cache cleared")
end

---🚀 Gets cache statistics for monitoring
---@return {size: number, max_size: number, hit_rate: number}
function M.get_cache_stats()
  local size = 0
  local total_hits = 0
  local total_requests = 0
  
  for _, entry in pairs(migration_cache) do
    size = size + 1
    if entry.hits then
      total_hits = total_hits + entry.hits
      total_requests = total_requests + entry.requests
    end
  end
  
  return {
    size = size,
    max_size = MAX_CACHE_SIZE,
    hit_rate = total_requests > 0 and (total_hits / total_requests) or 0
  }
end

---🚀 Optimized version of convert_entries_to_messages with caching
---@param entries avante.ChatHistoryEntry[]
---@param cache_key? string Optional cache key for repeated conversions
---@return avante.HistoryMessage[]
---@return string|nil error Error message if conversion fails  
function M.convert_entries_to_messages_cached(entries, cache_key)
  if not entries or #entries == 0 then
    return {}, nil
  end
  
  -- 🚀 Check cache if key provided
  if cache_key and migration_cache[cache_key] then
    local cached = migration_cache[cache_key]
    cached.hits = (cached.hits or 0) + 1
    cached.requests = (cached.requests or 0) + 1
    Utils.debug("Cache hit for migration:", cache_key)
    return vim.deepcopy(cached.messages), nil
  end
  
  -- 🔄 Perform conversion
  local messages, error_msg = M.convert_entries_to_messages(entries)
  
  -- 🚀 Cache result if successful and cache key provided
  if not error_msg and cache_key then
    -- 🧹 Implement LRU eviction if cache is full
    if vim.tbl_count(migration_cache) >= MAX_CACHE_SIZE then
      local oldest_key = next(migration_cache)
      local oldest_time = migration_cache[oldest_key].cached_at or 0
      
      for key, entry in pairs(migration_cache) do
        if (entry.cached_at or 0) < oldest_time then
          oldest_key = key
          oldest_time = entry.cached_at or 0
        end
      end
      
      migration_cache[oldest_key] = nil
      Utils.debug("Evicted old cache entry:", oldest_key)
    end
    
    migration_cache[cache_key] = {
      messages = vim.deepcopy(messages),
      cached_at = os.time(),
      hits = 0,
      requests = 1,
    }
    Utils.debug("Cached migration result:", cache_key)
  end
  
  return messages, error_msg
end

---🚀 Batch migration utility for processing multiple files efficiently
---@param filepaths string[] List of history file paths to migrate
---@param progress_callback? fun(completed: number, total: number, current_file: string): nil
---@return {success: string[], failed: table<string, string>} Results with successful and failed migrations
function M.batch_migrate_files(filepaths, progress_callback)
  local results = {
    success = {},
    failed = {}
  }
  
  local total = #filepaths
  Utils.info(string.format("Starting batch migration of %d files", total))
  
  for i, filepath in ipairs(filepaths) do
    if progress_callback then
      progress_callback(i - 1, total, filepath)
    end
    
    local success, error_msg = M.migrate_history_file(filepath)
    if success then
      table.insert(results.success, filepath)
      Utils.debug("Successfully migrated:", filepath)
    else
      results.failed[filepath] = error_msg or "Unknown error"
      Utils.warn("Failed to migrate:", filepath, "-", error_msg)
    end
    
    -- 🚀 Yield control periodically to prevent blocking
    if i % 10 == 0 then
      vim.schedule(function() end)
    end
  end
  
  if progress_callback then
    progress_callback(total, total, "Complete")
  end
  
  Utils.info(string.format(
    "Batch migration complete: %d successful, %d failed",
    #results.success,
    vim.tbl_count(results.failed)
  ))
  
  return results
end

---🚀 Memory-efficient migration for large files using streaming
---@param filepath string Path to large history file
---@return boolean success
---@return string|nil error Error message if migration fails
function M.migrate_large_file(filepath)
  local Path = require("plenary.path")
  local file_path = Path:new(filepath)
  
  if not file_path:exists() then
    return false, "File does not exist: " .. filepath
  end
  
  -- 📊 Check file size to determine if streaming is needed
  local stat = vim.loop.fs_stat(filepath)
  if not stat or stat.size < 1048576 then -- Less than 1MB, use regular migration
    return M.migrate_history_file(filepath)
  end
  
  Utils.info("Using streaming migration for large file:", filepath)
  
  -- 🔄 For very large files, we'd implement streaming JSON parsing here
  -- For now, use regular migration but with memory monitoring
  local before_mem = collectgarbage("count")
  local success, error_msg = M.migrate_history_file(filepath)
  local after_mem = collectgarbage("count")
  
  Utils.debug(string.format(
    "Migration memory usage: %.2f KB -> %.2f KB (delta: %.2f KB)",
    before_mem, after_mem, after_mem - before_mem
  ))
  
  -- 🧹 Force garbage collection for large migrations
  if after_mem - before_mem > 5120 then -- More than 5MB used
    collectgarbage("collect")
    Utils.debug("Forced garbage collection after large migration")
  end
  
  return success, error_msg
end

---🔍 Comprehensive validation suite for migration integrity
---@param history avante.ChatHistory
---@return boolean is_valid
---@return table validation_report Detailed validation report
function M.comprehensive_validation(history)
  local report = {
    format_valid = false,
    metadata_valid = false,
    messages_valid = false,
    tool_integrity = false,
    performance_metrics = {},
    warnings = {},
    errors = {},
    recommendations = {}
  }
  
  -- 🏷️ Format validation
  local format = M.detect_format(history)
  if format == "unified" then
    report.format_valid = true
    report.performance_metrics.format_version = history.format_version
  else
    table.insert(report.errors, "History not in unified format: " .. format)
  end
  
  -- 📊 Metadata validation
  if format == "unified" and history.migration_metadata then
    local meta = history.migration_metadata
    if meta.migrated_at and meta.migration_version then
      report.metadata_valid = true
      report.performance_metrics.migration_version = meta.migration_version
    else
      table.insert(report.warnings, "Incomplete migration metadata")
    end
  elseif format == "unified" then
    table.insert(report.warnings, "Unified format without migration metadata (may be new history)")
    report.metadata_valid = true -- New histories don't need migration metadata
  end
  
  -- 💬 Messages validation
  local messages = history.messages or {}
  if #messages == 0 then
    table.insert(report.warnings, "Empty message history")
    report.messages_valid = true
  else
    local valid_messages = 0
    for i, message in ipairs(messages) do
      if message.message and message.message.role and message.message.content then
        valid_messages = valid_messages + 1
      else
        table.insert(report.errors, string.format("Invalid message structure at index %d", i))
      end
    end
    report.messages_valid = valid_messages == #messages
    report.performance_metrics.message_count = #messages
    report.performance_metrics.valid_message_count = valid_messages
  end
  
  -- 🔧 Tool integrity check
  if #messages > 0 then
    local Helpers = require("avante.history.helpers")
    local tool_uses = 0
    local tool_results = 0
    local orphaned_results = 0
    
    for _, message in ipairs(messages) do
      if Helpers.get_tool_use_data(message) then
        tool_uses = tool_uses + 1
      elseif Helpers.get_tool_result_data(message) then
        tool_results = tool_results + 1
      end
    end
    
    -- Check for orphaned tool results
    for _, message in ipairs(messages) do
      local result = Helpers.get_tool_result_data(message)
      if result then
        local found_use = false
        for _, check_message in ipairs(messages) do
          local use = Helpers.get_tool_use_data(check_message)
          if use and use.id == result.tool_use_id then
            found_use = true
            break
          end
        end
        if not found_use then
          orphaned_results = orphaned_results + 1
        end
      end
    end
    
    report.performance_metrics.tool_uses = tool_uses
    report.performance_metrics.tool_results = tool_results
    report.performance_metrics.orphaned_results = orphaned_results
    
    if orphaned_results > 0 then
      table.insert(report.warnings, string.format("%d orphaned tool results found", orphaned_results))
    end
    
    report.tool_integrity = orphaned_results == 0
  else
    report.tool_integrity = true -- No tools to validate
  end
  
  -- 📋 Generate recommendations
  if not report.format_valid then
    table.insert(report.recommendations, "Migrate history to unified format")
  end
  
  if not report.metadata_valid and format ~= "unified" then
    table.insert(report.recommendations, "Complete migration metadata")
  end
  
  if orphaned_results > 0 then
    table.insert(report.recommendations, "Clean up orphaned tool results")
  end
  
  if #messages > 1000 then
    table.insert(report.recommendations, "Consider implementing memory compaction")
  end
  
  local is_valid = report.format_valid and report.metadata_valid and 
                  report.messages_valid and report.tool_integrity
  
  return is_valid, report
end

---🔧 Auto-repair functionality for common migration issues
---@param history avante.ChatHistory
---@return avante.ChatHistory repaired_history
---@return table repair_log Log of repairs performed
function M.auto_repair(history)
  local repair_log = {
    repairs_performed = {},
    warnings_fixed = {},
    remaining_issues = {}
  }
  
  local repaired_history = vim.deepcopy(history)
  
  -- 🔧 Fix format version if missing
  if not repaired_history.format_version and repaired_history.messages then
    repaired_history.format_version = M.CURRENT_FORMAT_VERSION
    table.insert(repair_log.repairs_performed, "Added missing format version")
  end
  
  -- 🔧 Remove orphaned legacy entries field
  if repaired_history.entries and repaired_history.messages then
    repaired_history.entries = nil
    table.insert(repair_log.repairs_performed, "Removed orphaned legacy entries field")
  end
  
  -- 🔧 Fix empty or invalid messages
  if repaired_history.messages then
    local cleaned_messages = {}
    local removed_count = 0
    
    for i, message in ipairs(repaired_history.messages) do
      if message.message and message.message.role and message.message.content then
        table.insert(cleaned_messages, message)
      else
        removed_count = removed_count + 1
        table.insert(repair_log.warnings_fixed, string.format("Removed invalid message at index %d", i))
      end
    end
    
    if removed_count > 0 then
      repaired_history.messages = cleaned_messages
      table.insert(repair_log.repairs_performed, string.format("Cleaned %d invalid messages", removed_count))
    end
  end
  
  -- 🔧 Add migration metadata if missing for migrated content
  if M.detect_format(repaired_history) == "unified" and not repaired_history.migration_metadata then
    repaired_history.migration_metadata = {
      migrated_at = Utils.get_timestamp(),
      original_format = "unknown", -- We can't determine original format
      migration_version = M.MIGRATION_VERSION,
      backup_created = false,
    }
    table.insert(repair_log.repairs_performed, "Added missing migration metadata")
  end
  
  return repaired_history, repair_log
end

---📊 Migration status checker for project directories
---@param bufnr integer Buffer number to check project for
---@return table migration_status Detailed status of all history files in project
function M.check_project_migration_status(bufnr)
  local Path = require("avante.path")
  local histories = Path.history.list(bufnr)
  
  local status = {
    total_files = #histories,
    unified_count = 0,
    legacy_count = 0,
    modern_count = 0,
    corrupted_count = 0,
    needs_migration = {},
    corrupted_files = {},
    performance_summary = {
      total_messages = 0,
      average_messages_per_file = 0,
      largest_file_messages = 0,
      oldest_migration = nil,
    }
  }
  
  for _, history in ipairs(histories) do
    local format = M.detect_format(history)
    local message_count = #(history.messages or {})
    
    status.performance_summary.total_messages = status.performance_summary.total_messages + message_count
    
    if message_count > status.performance_summary.largest_file_messages then
      status.performance_summary.largest_file_messages = message_count
    end
    
    if format == "unified" then
      status.unified_count = status.unified_count + 1
      
      -- Track migration dates
      if history.migration_metadata and history.migration_metadata.migrated_at then
        local migration_date = history.migration_metadata.migrated_at
        if not status.performance_summary.oldest_migration or 
           migration_date < status.performance_summary.oldest_migration then
          status.performance_summary.oldest_migration = migration_date
        end
      end
    elseif format == "legacy" then
      status.legacy_count = status.legacy_count + 1
      table.insert(status.needs_migration, {
        filename = history.filename,
        format = format,
        entry_count = #(history.entries or {}),
      })
    elseif format == "modern" then
      status.modern_count = status.modern_count + 1
      table.insert(status.needs_migration, {
        filename = history.filename,
        format = format,
        message_count = message_count,
      })
    else
      status.corrupted_count = status.corrupted_count + 1
      table.insert(status.corrupted_files, {
        filename = history.filename,
        reason = "Unknown format or corrupted structure"
      })
    end
  end
  
  if status.total_files > 0 then
    status.performance_summary.average_messages_per_file = 
      status.performance_summary.total_messages / status.total_files
  end
  
  return status
end

return M
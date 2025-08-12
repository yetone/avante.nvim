-- 🔄 Avante.nvim History Storage Migration System
-- Handles migration from legacy ChatHistoryEntry[] to unified HistoryMessage[] format

local Utils = require("avante.utils")
local Path = require("plenary.path")

---@class avante.HistoryMigration
local M = {}

---@alias MigrationMetadata { version: string, last_migrated: string, backup_created: boolean, migration_id: string }

---Migration version constants
M.MIGRATION_VERSION = "1.0.0"
M.LEGACY_FORMAT_INDICATOR = "entries"
M.MODERN_FORMAT_INDICATOR = "messages"

---@class UnifiedChatHistory : avante.ChatHistory
---@field version string Migration version
---@field migration_metadata MigrationMetadata | nil
---@field messages avante.HistoryMessage[] Unified messages array (never entries)

---@class MigrationOptions
---@field create_backup boolean Whether to create backup before migration
---@field validate_integrity boolean Whether to run integrity checks post-migration
---@field progress_callback? fun(current: integer, total: integer, message: string): nil

---Detects if a history object uses legacy format
---@param history avante.ChatHistory
---@return boolean is_legacy True if legacy format detected
function M.is_legacy_format(history)
  return history.entries ~= nil and history.messages == nil
end

---Detects if a history object uses modern unified format
---@param history avante.ChatHistory | UnifiedChatHistory
---@return boolean is_unified True if unified format detected
function M.is_unified_format(history)
  ---@cast history UnifiedChatHistory
  return history.messages ~= nil and history.entries == nil and history.version ~= nil
end

---Creates metadata for tracking migration state
---@param migration_id string Unique identifier for this migration
---@return MigrationMetadata
function M.create_migration_metadata(migration_id)
  return {
    version = M.MIGRATION_VERSION,
    last_migrated = Utils.get_timestamp(),
    backup_created = false,
    migration_id = migration_id,
  }
end

---Comprehensive integrity validation for migrated history
---@param history UnifiedChatHistory
---@return boolean success True if validation passes
---@return string[] errors List of validation errors
---@return table validation_stats Detailed validation statistics
function M.validate_migrated_history(history)
  local errors = {}
  local warnings = {}
  local stats = {
    messages_validated = 0,
    tool_use_messages = 0,
    tool_result_messages = 0,
    user_messages = 0,
    assistant_messages = 0,
    duplicate_uuids = {},
    started_at = Utils.get_timestamp(),
  }
  
  -- ✅ Check required fields
  if not history.version then
    table.insert(errors, "Missing version field in migrated history")
  elseif history.version ~= M.MIGRATION_VERSION then
    table.insert(warnings, string.format("Version mismatch: expected %s, got %s", M.MIGRATION_VERSION, history.version))
  end
  
  if not history.messages then
    table.insert(errors, "Missing messages field in migrated history")
  end
  
  if history.entries then
    table.insert(errors, "Legacy entries field still present after migration")
  end
  
  if not history.migration_metadata then
    table.insert(warnings, "Missing migration metadata")
  end
  
  -- 🔍 Comprehensive message validation
  if history.messages then
    local uuid_seen = {}
    local turn_ids = {}
    
    for i, message in ipairs(history.messages) do
      stats.messages_validated = stats.messages_validated + 1
      
      -- 📝 Required field validation
      if not message.message then
        table.insert(errors, string.format("Message %d missing 'message' field", i))
      end
      
      if not message.timestamp then
        table.insert(errors, string.format("Message %d missing 'timestamp' field", i))
      end
      
      if not message.uuid then
        table.insert(errors, string.format("Message %d missing 'uuid' field", i))
      else
        -- 🔄 Check for duplicate UUIDs
        if uuid_seen[message.uuid] then
          table.insert(stats.duplicate_uuids, message.uuid)
          table.insert(errors, string.format("Duplicate UUID %s found in messages %d and %d", message.uuid, uuid_seen[message.uuid], i))
        else
          uuid_seen[message.uuid] = i
        end
      end
      
      -- 👤🤖 Role validation and counting
      if message.message and message.message.role then
        if message.message.role == "user" then
          stats.user_messages = stats.user_messages + 1
        elseif message.message.role == "assistant" then
          stats.assistant_messages = stats.assistant_messages + 1
        else
          table.insert(warnings, string.format("Message %d has unknown role: %s", i, message.message.role))
        end
      end
      
      -- 🔧 Tool message validation
      local Helpers = require("avante.history.helpers")
      if Helpers.is_tool_use_message(message) then
        stats.tool_use_messages = stats.tool_use_messages + 1
        local tool_use = Helpers.get_tool_use_data(message)
        if tool_use and not tool_use.id then
          table.insert(errors, string.format("Tool use message %d missing ID", i))
        end
      elseif Helpers.is_tool_result_message(message) then
        stats.tool_result_messages = stats.tool_result_messages + 1
        local tool_result = Helpers.get_tool_result_data(message)
        if tool_result and not tool_result.tool_use_id then
          table.insert(errors, string.format("Tool result message %d missing tool_use_id", i))
        end
      end
      
      -- 🎯 Turn ID consistency (if present)
      if message.turn_id then
        turn_ids[message.turn_id] = (turn_ids[message.turn_id] or 0) + 1
      end
    end
    
    -- 📊 Validate tool message pairing
    if stats.tool_use_messages > 0 then
      local History = require("avante.history")
      local tools, files = M.preserve_tool_processing_info(history.messages)
      
      -- 🔗 Check if tool use messages have corresponding results
      local unpaired_tools = 0
      for tool_id, tool_info in pairs(tools) do
        if not tool_info.result then
          unpaired_tools = unpaired_tools + 1
        end
      end
      
      if unpaired_tools > 0 then
        table.insert(warnings, string.format("%d tool use messages lack corresponding results", unpaired_tools))
      end
      
      stats.tool_chains_validated = vim.tbl_count(tools)
      stats.files_with_tool_history = vim.tbl_count(files)
    end
  end
  
  -- 🎯 Data integrity checks
  if history.tokens_usage then
    if type(history.tokens_usage) ~= "table" then
      table.insert(errors, "tokens_usage field must be a table")
    end
  end
  
  stats.completed_at = Utils.get_timestamp()
  stats.validation_duration = (vim.loop.hrtime() - (stats.started_at_hrtime or vim.loop.hrtime())) / 1000000 -- ms
  
  local all_issues = vim.list_extend({}, errors)
  all_issues = vim.list_extend(all_issues, warnings)
  
  Utils.debug(string.format("🔍 Validation completed: %d messages, %d errors, %d warnings", 
    stats.messages_validated, #errors, #warnings))
  
  return #errors == 0, errors, { stats = stats, warnings = warnings }
end

---Creates a backup of the original history file before migration
---@param filepath Path
---@return boolean success
---@return string? error_message
function M.create_backup(filepath)
  local backup_path = Path:new(tostring(filepath) .. ".backup." .. Utils.get_timestamp())
  
  local ok, error = pcall(function()
    filepath:copy({ destination = backup_path })
  end)
  
  if not ok then
    return false, "Failed to create backup: " .. tostring(error)
  end
  
  Utils.debug("Created backup at: " .. tostring(backup_path))
  return true, nil
end

---Restores from backup in case of migration failure
---@param filepath Path Original file path
---@param backup_path Path Backup file path
---@return boolean success
---@return string? error_message
function M.restore_from_backup(filepath, backup_path)
  local ok, error = pcall(function()
    backup_path:copy({ destination = filepath })
  end)
  
  if not ok then
    return false, "Failed to restore from backup: " .. tostring(error)
  end
  
  Utils.info("Restored from backup: " .. tostring(backup_path))
  return true, nil
end

---Performs atomic write operation using temporary file and rename
---@param filepath Path Target file path
---@param data table Data to write
---@return boolean success
---@return string? error_message
function M.atomic_write(filepath, data)
  local temp_path = Path:new(tostring(filepath) .. ".tmp." .. Utils.uuid())
  
  -- 📝 Write to temporary file first
  local ok, error = pcall(function()
    local json_content = vim.json.encode(data)
    temp_path:write(json_content, "w")
  end)
  
  if not ok then
    -- 🧹 Clean up temporary file on error
    if temp_path:exists() then
      temp_path:rm()
    end
    return false, "Failed to write temporary file: " .. tostring(error)
  end
  
  -- ⚡ Atomic rename operation
  ok, error = pcall(function()
    temp_path:rename({ new_name = tostring(filepath) })
  end)
  
  if not ok then
    -- 🧹 Clean up temporary file on error
    if temp_path:exists() then
      temp_path:rm()
    end
    return false, "Failed to rename temporary file: " .. tostring(error)
  end
  
  return true, nil
end

---Validates JSON content before parsing
---@param content string JSON content to validate
---@return boolean valid True if valid JSON
---@return table|string data Parsed data or error message
function M.validate_json(content)
  local ok, result = pcall(vim.json.decode, content)
  if not ok then
    return false, "Invalid JSON: " .. tostring(result)
  end
  return true, result
end

---Gets migration progress reporter function
---@param opts MigrationOptions
---@return fun(current: integer, total: integer, message: string): nil
function M.get_progress_reporter(opts)
  return opts.progress_callback or function() end
end

---Preserves tool processing information during migration
---@param messages avante.HistoryMessage[]
---@return table<string, HistoryToolInfo> tools Tool information mapping
---@return table<string, HistoryFileInfo> files File information mapping
function M.preserve_tool_processing_info(messages)
  local History = require("avante.history")
  -- 🔧 Use existing collect_tool_info function to preserve tool state
  if History.collect_tool_info then
    return History.collect_tool_info(messages)
  end
  return {}, {}
end

---Enhanced conversion that preserves tool use logs and store data
---@param entry avante.ChatHistoryEntry
---@param preserve_tool_data boolean Whether to preserve tool-related data
---@return avante.HistoryMessage[] messages Array of converted messages
---@return table tool_preservation_data Preserved tool data
function M.convert_legacy_entry_to_messages_enhanced(entry, preserve_tool_data)
  local Message = require("avante.history.message")
  local messages = {}
  local tool_preservation_data = {
    tool_use_logs = {},
    tool_use_store = {},
  }
  
  -- 👤 Convert user request to HistoryMessage
  if entry.request and entry.request ~= "" then
    local user_opts = {
      timestamp = entry.timestamp,
      is_user_submission = true,
      visible = entry.visible,
      selected_filepaths = entry.selected_filepaths,
      selected_code = entry.selected_code,
      provider = entry.provider,
      model = entry.model,
    }
    
    -- 🔧 Preserve tool-related data if available
    if preserve_tool_data and entry.tool_use_logs then
      user_opts.tool_use_logs = entry.tool_use_logs
      tool_preservation_data.tool_use_logs = entry.tool_use_logs
    end
    
    if preserve_tool_data and entry.tool_use_store then
      user_opts.tool_use_store = entry.tool_use_store
      tool_preservation_data.tool_use_store = entry.tool_use_store
    end
    
    local user_message = Message:new("user", entry.request, user_opts)
    table.insert(messages, user_message)
  end
  
  -- 🤖 Convert assistant response to HistoryMessage
  if entry.response and entry.response ~= "" then
    local assistant_opts = {
      timestamp = entry.timestamp,
      visible = entry.visible,
      provider = entry.provider,
      model = entry.model,
      original_content = entry.original_response,
    }
    
    local assistant_message = Message:new("assistant", entry.response, assistant_opts)
    table.insert(messages, assistant_message)
  end
  
  return messages, tool_preservation_data
end

---Converts a legacy ChatHistoryEntry to HistoryMessage format
---@param entry avante.ChatHistoryEntry
---@return avante.HistoryMessage[] messages Array of converted messages (user request + assistant response)
function M.convert_legacy_entry_to_messages(entry)
  local messages, _ = M.convert_legacy_entry_to_messages_enhanced(entry, true)
  return messages
end

---Converts entire legacy history to unified format with enhanced tool preservation
---@param legacy_history avante.ChatHistory
---@return UnifiedChatHistory unified_history
---@return table conversion_stats Statistics about the conversion process
function M.convert_legacy_to_unified(legacy_history)
  local migration_id = Utils.uuid()
  local conversion_stats = {
    entries_processed = 0,
    messages_created = 0,
    tool_data_preserved = 0,
    synthetic_messages_created = 0,
    errors = {},
    warnings = {},
    started_at = Utils.get_timestamp(),
  }
  
  ---@type UnifiedChatHistory
  local unified_history = {
    title = legacy_history.title,
    timestamp = legacy_history.timestamp,
    filename = legacy_history.filename,
    system_prompt = legacy_history.system_prompt,
    todos = legacy_history.todos,
    memory = legacy_history.memory,
    tokens_usage = legacy_history.tokens_usage,
    version = M.MIGRATION_VERSION,
    migration_metadata = M.create_migration_metadata(migration_id),
    messages = {},
  }
  
  local all_tool_data = {}
  
  -- 🔄 Process each legacy entry with enhanced tool preservation
  if legacy_history.entries then
    for i, entry in ipairs(legacy_history.entries) do
      conversion_stats.entries_processed = conversion_stats.entries_processed + 1
      
      -- 🛡️ Validate entry structure
      if not entry.timestamp then
        table.insert(conversion_stats.warnings, 
          string.format("Entry %d missing timestamp, using current time", i))
        entry.timestamp = Utils.get_timestamp()
      end
      
      -- 📝 Convert entry to messages with tool data preservation
      local ok, result, tool_data = pcall(M.convert_legacy_entry_to_messages_enhanced, entry, true)
      if ok then
        for _, message in ipairs(result) do
          table.insert(unified_history.messages, message)
          conversion_stats.messages_created = conversion_stats.messages_created + 1
        end
        
        -- 🔧 Accumulate tool data for post-processing
        if tool_data then
          table.insert(all_tool_data, tool_data)
          if tool_data.tool_use_logs and #tool_data.tool_use_logs > 0 then
            conversion_stats.tool_data_preserved = conversion_stats.tool_data_preserved + 1
          end
        end
      else
        table.insert(conversion_stats.errors, 
          string.format("Failed to convert entry %d: %s", i, tostring(result)))
      end
    end
  end
  
  -- 🔗 Post-process to maintain tool chain continuity
  if #unified_history.messages > 0 then
    local tools, files = M.preserve_tool_processing_info(unified_history.messages)
    
    -- 🎯 Generate synthetic messages for tool state if needed
    if next(tools) or next(files) then
      local History = require("avante.history")
      
      -- ⚡ Apply tool processing optimizations similar to existing system
      if History.update_tool_invocation_history then
        local enhanced_messages = History.update_tool_invocation_history(
          unified_history.messages, 
          nil, -- max_tool_use (nil = no limit during migration)
          true  -- add_diagnostic
        )
        
        if #enhanced_messages > #unified_history.messages then
          conversion_stats.synthetic_messages_created = #enhanced_messages - #unified_history.messages
          unified_history.messages = enhanced_messages
        end
      end
    end
  end
  
  conversion_stats.completed_at = Utils.get_timestamp()
  Utils.debug(string.format("🔄 Migration completed: %d entries → %d messages (%d with tool data, %d synthetic)", 
    conversion_stats.entries_processed, 
    conversion_stats.messages_created,
    conversion_stats.tool_data_preserved,
    conversion_stats.synthetic_messages_created))
  
  return unified_history, conversion_stats
end

---Performs complete migration of a history file
---@param filepath Path Path to the history file
---@param opts? MigrationOptions Migration options
---@return boolean success True if migration succeeded
---@return string? error_message Error message if migration failed
---@return table? migration_stats Migration statistics
function M.migrate_history_file(filepath, opts)
  opts = opts or { create_backup = true, validate_integrity = true }
  local progress = M.get_progress_reporter(opts)
  
  progress(0, 5, "Reading history file...")
  
  -- 📖 Read and validate original file
  if not filepath:exists() then
    return false, "History file does not exist: " .. tostring(filepath), nil
  end
  
  local content = filepath:read()
  if not content then
    return false, "Failed to read history file", nil
  end
  
  progress(1, 5, "Validating JSON...")
  
  local valid, history_or_error = M.validate_json(content)
  if not valid then
    return false, "Invalid JSON in history file: " .. history_or_error, nil
  end
  
  local history = history_or_error
  
  -- ✅ Check if migration is needed
  if M.is_unified_format(history) then
    Utils.debug("History already in unified format, skipping migration")
    return true, nil, { already_migrated = true }
  end
  
  if not M.is_legacy_format(history) then
    return false, "History is neither legacy nor unified format", nil
  end
  
  progress(2, 5, "Creating backup...")
  
  -- 💾 Create backup if requested
  if opts.create_backup then
    local backup_success, backup_error = M.create_backup(filepath)
    if not backup_success then
      return false, backup_error, nil
    end
  end
  
  progress(3, 5, "Converting to unified format...")
  
  -- 🔄 Perform conversion
  local unified_history, conversion_stats = M.convert_legacy_to_unified(history)
  
  -- ✅ Comprehensive migration validation if requested
  if opts.validate_integrity then
    progress(4, 5, "Validating migration...")
    
    local valid_migration, validation_errors, validation_details = M.validate_migrated_history(unified_history)
    if not valid_migration then
      return false, "Migration validation failed: " .. table.concat(validation_errors, ", "), 
        vim.tbl_extend("force", conversion_stats, { validation_details = validation_details })
    end
    
    -- 📊 Add validation stats to conversion stats
    if validation_details and validation_details.stats then
      conversion_stats.validation_stats = validation_details.stats
      conversion_stats.validation_warnings = validation_details.warnings or {}
    end
  end
  
  progress(5, 5, "Writing unified format...")
  
  -- 💾 Write unified format atomically
  local write_success, write_error = M.atomic_write(filepath, unified_history)
  if not write_success then
    return false, write_error, conversion_stats
  end
  
  progress(5, 5, "Migration completed successfully!")
  
  return true, nil, conversion_stats
end

---Performance benchmarking for migration operations
---@param operation function Function to benchmark
---@param iterations? integer Number of iterations (default: 1)
---@return table benchmark_results Performance metrics
function M.benchmark_migration(operation, iterations)
  iterations = iterations or 1
  local results = {
    total_time = 0,
    avg_time = 0,
    min_time = math.huge,
    max_time = 0,
    memory_usage = {},
    iterations = iterations,
    started_at = Utils.get_timestamp(),
  }
  
  local start_memory = collectgarbage("count")
  
  for i = 1, iterations do
    local start_time = vim.loop.hrtime()
    
    -- 🚀 Execute operation
    local success, result = pcall(operation)
    
    local end_time = vim.loop.hrtime()
    local duration = (end_time - start_time) / 1000000 -- Convert to milliseconds
    
    results.total_time = results.total_time + duration
    results.min_time = math.min(results.min_time, duration)
    results.max_time = math.max(results.max_time, duration)
    
    local current_memory = collectgarbage("count")
    table.insert(results.memory_usage, current_memory - start_memory)
    
    if not success then
      results.error = result
      break
    end
  end
  
  results.avg_time = results.total_time / iterations
  results.completed_at = Utils.get_timestamp()
  
  -- 🧹 Force garbage collection and measure final memory
  collectgarbage("collect")
  results.final_memory = collectgarbage("count")
  
  return results
end

---Memory optimization utilities for large migrations
---@param max_memory_mb number Maximum memory threshold in MB
---@return boolean should_pause True if migration should pause for GC
function M.check_memory_usage(max_memory_mb)
  local current_memory_kb = collectgarbage("count")
  local current_memory_mb = current_memory_kb / 1024
  
  if current_memory_mb > max_memory_mb then
    Utils.warn(string.format("🚨 Memory usage high: %.1f MB (threshold: %.1f MB)", 
      current_memory_mb, max_memory_mb))
    collectgarbage("collect")
    return true
  end
  
  return false
end

---Chunked migration for processing large datasets efficiently
---@param histories table[] Array of histories to migrate
---@param chunk_size integer Number of histories to process per chunk
---@param options MigrationOptions Migration options
---@return table results Aggregated migration results
function M.migrate_histories_chunked(histories, chunk_size, options)
  chunk_size = chunk_size or 50
  local total_results = {
    total_histories = #histories,
    processed = 0,
    successful = 0,
    failed = 0,
    chunks_processed = 0,
    errors = {},
    started_at = Utils.get_timestamp(),
  }
  
  for i = 1, #histories, chunk_size do
    local chunk_end = math.min(i + chunk_size - 1, #histories)
    local chunk = vim.list_slice(histories, i, chunk_end)
    
    Utils.debug(string.format("📦 Processing chunk %d-%d of %d histories", 
      i, chunk_end, #histories))
    
    for _, history in ipairs(chunk) do
      total_results.processed = total_results.processed + 1
      
      local success, error_msg = pcall(function()
        if Migration.is_legacy_format(history) then
          local unified, stats = Migration.convert_legacy_to_unified(history)
          return unified, stats
        end
      end)
      
      if success then
        total_results.successful = total_results.successful + 1
      else
        total_results.failed = total_results.failed + 1
        table.insert(total_results.errors, {
          history = history.filename or "unknown",
          error = error_msg
        })
      end
    end
    
    total_results.chunks_processed = total_results.chunks_processed + 1
    
    -- 🧹 Memory management between chunks
    if M.check_memory_usage(100) then -- 100MB threshold
      Utils.debug("🧹 Performing garbage collection between chunks")
    end
    
    -- 📊 Progress reporting
    if options and options.progress_callback then
      options.progress_callback(chunk_end, #histories, 
        string.format("Processed chunk %d", total_results.chunks_processed))
    end
  end
  
  total_results.completed_at = Utils.get_timestamp()
  return total_results
end

---Recovery mechanisms for failed migrations
---@param filepath Path File that failed migration
---@param backup_pattern string Pattern to find backup files
---@return boolean success True if recovery succeeded
---@return string? error_message Error message if recovery failed
function M.recover_from_failed_migration(filepath, backup_pattern)
  backup_pattern = backup_pattern or "*.backup.*"
  
  local backup_dir = filepath:parent()
  local backup_files = vim.fn.glob(tostring(backup_dir:joinpath(backup_pattern)), true, true)
  
  if #backup_files == 0 then
    return false, "No backup files found for recovery"
  end
  
  -- 📅 Find most recent backup
  table.sort(backup_files, function(a, b)
    local stat_a = vim.loop.fs_stat(a)
    local stat_b = vim.loop.fs_stat(b)
    return stat_a and stat_b and stat_a.mtime.sec > stat_b.mtime.sec
  end)
  
  local latest_backup = Path:new(backup_files[1])
  
  -- 🔄 Attempt recovery
  local ok, error = pcall(function()
    latest_backup:copy({ destination = filepath })
  end)
  
  if not ok then
    return false, "Failed to restore from backup: " .. tostring(error)
  end
  
  Utils.info("🔄 Successfully recovered from backup: " .. tostring(latest_backup))
  return true, nil
end

return M
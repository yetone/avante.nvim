local Utils = require("avante.utils")
local Migration = require("avante.history.migration")
local Converter = require("avante.history.converter")
local AtomicStorage = require("avante.history.atomic_storage")
local ToolProcessor = require("avante.history.tool_processor")
local Path = require("plenary.path")

---@class avante.AutoMigrator
local M = {}

--- 🚀 Auto-migration configuration
M.AUTO_MIGRATION_ENABLED = true
M.MIGRATION_PROGRESS_THRESHOLD = 100 -- Show progress for files with >100 messages
M.MAX_CONCURRENT_MIGRATIONS = 3
M.MIGRATION_TIMEOUT_MS = 60000 -- 1 minute timeout per file

--- 📊 Migration session tracking
---@class avante.MigrationSession
---@field session_id string Unique session identifier
---@field start_time number Session start timestamp
---@field files_processed number Number of files processed
---@field files_migrated number Number of files successfully migrated
---@field files_failed number Number of files that failed migration
---@field errors string[] Collection of migration errors
---@field warnings string[] Collection of migration warnings
---@field total_messages_migrated number Total messages migrated across all files
---@field total_time_ms number Total migration time in milliseconds

--- 🔍 Comprehensive format detection with heuristics
---@param history avante.ChatHistory | avante.UnifiedChatHistory History data to analyze
---@return string format "legacy", "unified", "hybrid", or "unknown"
---@return number confidence Confidence level (0-1) of format detection
---@return table detection_details Detailed analysis of format characteristics
function M.detect_format_with_confidence(history)
  local details = {
    has_entries = false,
    has_messages = false,
    has_version = false,
    has_migration_metadata = false,
    entries_count = 0,
    messages_count = 0,
    version = nil,
    structure_indicators = {},
  }
  
  -- 📋 Basic structure analysis
  if history.entries then
    details.has_entries = true
    details.entries_count = #history.entries
    table.insert(details.structure_indicators, "has_entries")
  end
  
  if history.messages then
    details.has_messages = true
    details.messages_count = #history.messages
    table.insert(details.structure_indicators, "has_messages")
  end
  
  if history.version then
    details.has_version = true
    details.version = history.version
    table.insert(details.structure_indicators, "has_version")
  end
  
  if history.migration_metadata then
    details.has_migration_metadata = true
    table.insert(details.structure_indicators, "has_migration_metadata")
  end
  
  -- 🧠 Format detection logic with confidence scoring
  local format = "unknown"
  local confidence = 0
  
  if details.has_migration_metadata and details.has_version and details.version >= Migration.CURRENT_VERSION then
    -- 🎯 Clear unified format indicators
    format = "unified"
    confidence = 0.95
  elseif details.has_entries and not details.has_messages and not details.has_version then
    -- 🏛️ Clear legacy format indicators
    format = "legacy"
    confidence = 0.90
  elseif details.has_entries and details.has_messages then
    -- 🔀 Hybrid format detected
    format = "hybrid"
    confidence = 0.85
  elseif details.has_messages and details.has_version and details.version >= Migration.CURRENT_VERSION then
    -- ✨ Modern unified format
    format = "unified"
    confidence = 0.80
  elseif details.has_messages and not details.has_entries then
    -- 🆕 Likely unified format without explicit version
    format = "unified"
    confidence = 0.70
  elseif details.has_entries and not details.has_messages then
    -- 🏛️ Likely legacy format
    format = "legacy"
    confidence = 0.75
  end
  
  Utils.debug(string.format("🔍 Format detection: %s (confidence: %.2f)", format, confidence))
  return format, confidence, details
end

--- 🎯 Determine if migration is needed and beneficial
---@param history avante.ChatHistory | avante.UnifiedChatHistory History to analyze
---@param filepath Path File path for context
---@return boolean needs_migration True if migration is recommended
---@return string reason Reason for migration decision
---@return table migration_plan Planned migration steps
function M.should_migrate(history, filepath)
  local format, confidence, details = M.detect_format_with_confidence(history)
  
  local migration_plan = {
    format_detected = format,
    confidence = confidence,
    steps = {},
    estimated_duration_ms = 0,
    backup_recommended = true,
    complexity = "low",
  }
  
  -- 🏛️ Legacy format definitely needs migration
  if format == "legacy" and confidence >= 0.7 then
    migration_plan.steps = {
      "detect_legacy_format",
      "create_backup",
      "convert_entries_to_messages",
      "preserve_tool_processing",
      "validate_conversion",
      "atomic_write_unified_format"
    }
    migration_plan.estimated_duration_ms = details.entries_count * 10 + 500 -- Rough estimate
    migration_plan.complexity = details.entries_count > 50 and "high" or "medium"
    
    return true, string.format("Legacy format detected (%d entries, %.0f%% confidence)", 
                              details.entries_count, confidence * 100), migration_plan
  end
  
  -- 🔀 Hybrid format should be normalized
  if format == "hybrid" and confidence >= 0.8 then
    migration_plan.steps = {
      "detect_hybrid_format",
      "create_backup",
      "merge_entries_and_messages",
      "normalize_to_unified_format",
      "validate_merge",
      "atomic_write_unified_format"
    }
    migration_plan.estimated_duration_ms = (details.entries_count + details.messages_count) * 8 + 300
    migration_plan.complexity = (details.entries_count + details.messages_count) > 100 and "high" or "medium"
    
    return true, string.format("Hybrid format detected (%d entries + %d messages, %.0f%% confidence)", 
                              details.entries_count, details.messages_count, confidence * 100), migration_plan
  end
  
  -- ✨ Already unified format
  if format == "unified" and confidence >= 0.8 then
    return false, string.format("Already in unified format (%.0f%% confidence)", confidence * 100), migration_plan
  end
  
  -- 🤷 Uncertain format - be conservative
  return false, string.format("Uncertain format detection (%s, %.0f%% confidence)", format, confidence * 100), migration_plan
end

--- 📊 Progress reporting for large migrations
---@param session avante.MigrationSession Migration session
---@param current_file string Current file being processed
---@param total_files number Total files to process
---@param file_progress number Progress within current file (0-1)
function M.report_migration_progress(session, current_file, total_files, file_progress)
  local overall_progress = (session.files_processed + file_progress) / total_files
  local elapsed_ms = (os.time() * 1000) - session.start_time
  local estimated_total_ms = elapsed_ms / overall_progress
  local eta_ms = estimated_total_ms - elapsed_ms
  
  Utils.info(string.format("🚀 Migration Progress [%s]: %.1f%% (%d/%d files) - ETA: %.1fs", 
                           session.session_id:sub(1, 8), 
                           overall_progress * 100, 
                           session.files_processed + 1, 
                           total_files,
                           eta_ms / 1000))
  
  if file_progress > 0 then
    Utils.debug(string.format("📁 Processing %s: %.1f%% complete", current_file, file_progress * 100))
  end
end

--- 🔄 Migrate single history file with comprehensive error handling
---@param filepath Path History file to migrate
---@param session avante.MigrationSession Migration session for tracking
---@return boolean success True if migration succeeded
---@return string | nil error Error message if migration failed
---@return table migration_result Detailed migration result
function M.migrate_single_file(filepath, session)
  local migration_start = os.time() * 1000
  local operation_id = Utils.uuid()
  
  local migration_result = {
    filepath = tostring(filepath),
    operation_id = operation_id,
    start_time = migration_start,
    end_time = nil,
    duration_ms = 0,
    original_format = "unknown",
    backup_path = nil,
    messages_migrated = 0,
    tool_chains_preserved = 0,
    validation_passed = false,
    warnings = {},
    errors = {},
  }
  
  -- 📁 Load and analyze history file
  local history
  local load_ok, load_err = pcall(function()
    local content = filepath:read()
    history = vim.json.decode(content)
  end)
  
  if not load_ok then
    local error_msg = "Failed to load history file: " .. (load_err or "unknown error")
    table.insert(migration_result.errors, error_msg)
    migration_result.end_time = os.time() * 1000
    migration_result.duration_ms = migration_result.end_time - migration_start
    return false, error_msg, migration_result
  end
  
  -- 🔍 Check if migration is needed
  local needs_migration, reason, plan = M.should_migrate(history, filepath)
  if not needs_migration then
    Utils.debug(string.format("📁 Skipping %s: %s", tostring(filepath), reason))
    migration_result.end_time = os.time() * 1000
    migration_result.duration_ms = migration_result.end_time - migration_start
    return true, "No migration needed: " .. reason, migration_result
  end
  
  migration_result.original_format = plan.format_detected
  Utils.info(string.format("🔄 Migrating %s: %s", tostring(filepath), reason))
  
  -- 🛡️ Perform migration with error handling
  local migrate_ok, migrate_err = pcall(function()
    -- 💾 Create backup
    migration_result.backup_path = AtomicStorage.create_atomic_backup(filepath, operation_id)
    if not migration_result.backup_path then
      error("Failed to create backup")
    end
    
    -- 🔄 Convert legacy format
    local converted_history, convert_success, errors, warnings = Converter.convert_legacy_history(history)
    migration_result.warnings = warnings
    migration_result.errors = errors
    
    if not convert_success then
      error("Format conversion failed: " .. table.concat(errors, "; "))
    end
    
    -- 🛠️ Process tool chains with migration context
    local migration_context = {
      operation_id = operation_id,
      session_id = session.session_id,
      original_format = migration_result.original_format,
    }
    
    converted_history.messages = ToolProcessor.process_tools_with_migration_context(
      converted_history.messages, 
      nil, -- No tool limit
      true, -- Add diagnostics
      migration_context
    )
    
    -- 📊 Update migration result with conversion stats
    migration_result.messages_migrated = #converted_history.messages
    if converted_history.migration_metadata and converted_history.migration_metadata.conversion_stats then
      local stats = converted_history.migration_metadata.conversion_stats
      migration_result.tool_chains_preserved = stats.entries_with_selected_code or 0
    end
    
    -- ✅ Validate migration
    local validation_ok, validation_error = Migration.validate_migration(history, converted_history)
    if not validation_ok then
      error("Migration validation failed: " .. (validation_error or "unknown error"))
    end
    migration_result.validation_passed = true
    
    -- ⚡ Atomic write of migrated data
    local write_result = AtomicStorage.atomic_write(
      filepath, 
      vim.json.encode(converted_history), 
      operation_id,
      false -- Don't create another backup
    )
    
    if not write_result.success then
      error("Atomic write failed: " .. (write_result.error or "unknown error"))
    end
  end)
  
  migration_result.end_time = os.time() * 1000
  migration_result.duration_ms = migration_result.end_time - migration_start
  
  if migrate_ok then
    Utils.info(string.format("✅ Successfully migrated %s in %.1fs", 
                             tostring(filepath), migration_result.duration_ms / 1000))
    session.files_migrated = session.files_migrated + 1
    session.total_messages_migrated = session.total_messages_migrated + migration_result.messages_migrated
    return true, nil, migration_result
  else
    local error_msg = migrate_err or "Unknown migration error"
    table.insert(migration_result.errors, error_msg)
    session.files_failed = session.files_failed + 1
    table.insert(session.errors, string.format("%s: %s", tostring(filepath), error_msg))
    
    -- 🔄 Attempt rollback if backup exists
    if migration_result.backup_path then
      local rollback_result = AtomicStorage.atomic_rollback(filepath, migration_result.backup_path, operation_id)
      if rollback_result.success then
        Utils.info("🔄 Successfully rolled back failed migration")
        table.insert(migration_result.warnings, "Migration failed but was rolled back successfully")
      else
        Utils.error("❌ Failed to rollback migration: " .. (rollback_result.error or "unknown error"))
        table.insert(migration_result.errors, "Rollback also failed: " .. (rollback_result.error or ""))
      end
    end
    
    return false, error_msg, migration_result
  end
end

--- 🚀 Batch migrate multiple history files with progress reporting
---@param directory_path Path Directory containing history files
---@param max_concurrent number | nil Maximum concurrent migrations (default: 3)
---@return avante.MigrationSession session Migration session results
function M.batch_migrate_directory(directory_path, max_concurrent)
  max_concurrent = max_concurrent or M.MAX_CONCURRENT_MIGRATIONS
  
  local session = {
    session_id = Utils.uuid(),
    start_time = os.time() * 1000,
    files_processed = 0,
    files_migrated = 0,
    files_failed = 0,
    errors = {},
    warnings = {},
    total_messages_migrated = 0,
    total_time_ms = 0,
  }
  
  Utils.info(string.format("🚀 Starting batch migration session: %s", session.session_id:sub(1, 8)))
  
  -- 📁 Find all history files
  local history_files = {}
  if directory_path:exists() then
    local files = vim.fn.glob(tostring(directory_path:joinpath("*.json")), false, true)
    for _, file_path in ipairs(files) do
      local filename = vim.fn.fnamemodify(file_path, ":t")
      if filename ~= "metadata.json" then
        table.insert(history_files, Path:new(file_path))
      end
    end
  end
  
  if #history_files == 0 then
    Utils.debug("📁 No history files found for migration")
    session.total_time_ms = (os.time() * 1000) - session.start_time
    return session
  end
  
  Utils.info(string.format("📊 Found %d history files for potential migration", #history_files))
  
  -- 🔄 Process files with progress reporting
  for i, filepath in ipairs(history_files) do
    session.files_processed = session.files_processed + 1
    
    -- 📊 Report progress for large batches
    if #history_files >= M.MIGRATION_PROGRESS_THRESHOLD then
      M.report_migration_progress(session, tostring(filepath), #history_files, 0)
    end
    
    -- 🔄 Migrate single file
    local success, error, result = M.migrate_single_file(filepath, session)
    
    -- 📝 Collect warnings
    for _, warning in ipairs(result.warnings or {}) do
      table.insert(session.warnings, warning)
    end
    
    -- 📊 Update progress
    if #history_files >= M.MIGRATION_PROGRESS_THRESHOLD then
      M.report_migration_progress(session, tostring(filepath), #history_files, 1)
    end
  end
  
  session.total_time_ms = (os.time() * 1000) - session.start_time
  
  -- 📊 Final session summary
  Utils.info(string.format("🎉 Batch migration completed: %d migrated, %d failed, %d total messages migrated in %.2fs", 
                           session.files_migrated, 
                           session.files_failed, 
                           session.total_messages_migrated,
                           session.total_time_ms / 1000))
  
  if session.files_failed > 0 then
    Utils.warn(string.format("⚠️  %d files failed migration:", session.files_failed))
    for _, error in ipairs(session.errors) do
      Utils.warn("  - " .. error)
    end
  end
  
  if #session.warnings > 0 then
    Utils.debug(string.format("📝 %d warnings during migration", #session.warnings))
  end
  
  return session
end

--- 🎯 Auto-migrate on history load (main entry point)
---@param history avante.ChatHistory | avante.UnifiedChatHistory Loaded history
---@param filepath Path History file path
---@return avante.ChatHistory | avante.UnifiedChatHistory migrated_history Potentially migrated history
---@return boolean was_migrated True if migration was performed
function M.auto_migrate_on_load(history, filepath)
  if not M.AUTO_MIGRATION_ENABLED then
    return history, false
  end
  
  -- 🔍 Check if migration is needed
  local needs_migration, reason = M.should_migrate(history, filepath)
  if not needs_migration then
    return history, false
  end
  
  Utils.info(string.format("🔄 Auto-migrating on load: %s", reason))
  
  -- 🚀 Create single-file migration session
  local session = {
    session_id = "auto_" .. Utils.uuid():sub(1, 8),
    start_time = os.time() * 1000,
    files_processed = 0,
    files_migrated = 0,
    files_failed = 0,
    errors = {},
    warnings = {},
    total_messages_migrated = 0,
    total_time_ms = 0,
  }
  
  -- 🔄 Perform migration
  local success, error, result = M.migrate_single_file(filepath, session)
  
  if success and result.validation_passed then
    -- 🔄 Reload migrated history
    local migrated_content = filepath:read()
    local migrated_history = vim.json.decode(migrated_content)
    Utils.info("✅ Auto-migration completed successfully")
    return migrated_history, true
  else
    Utils.error(string.format("❌ Auto-migration failed: %s", error or "unknown error"))
    return history, false
  end
end

return M
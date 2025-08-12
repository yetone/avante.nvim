-- 🚀 Automatic migration system for Avante.nvim history storage
-- Detects legacy format and automatically triggers migration on first load

local Utils = require("avante.utils")
local Migration = require("avante.history.migration")

local M = {}

-- 📊 Migration state tracking
---@class AutoMigrationState
---@field enabled boolean
---@field migration_in_progress boolean
---@field last_migration_check string | nil
---@field migration_statistics table<string, integer>
local state = {
  enabled = true,
  migration_in_progress = false,
  last_migration_check = nil,
  migration_statistics = {
    files_migrated = 0,
    files_failed = 0,
    total_entries_converted = 0,
    total_messages_generated = 0
  }
}

-- ⚙️ Configuration options
---@class AutoMigrationConfig
---@field enabled boolean Enable/disable auto migration
---@field progress_reporting boolean Show progress during migration
---@field backup_enabled boolean Create backups before migration
---@field performance_targets table Performance targets for migration
local config = {
  enabled = true,
  progress_reporting = true,
  backup_enabled = true,
  performance_targets = {
    max_time_per_file_ms = 500,
    max_memory_usage_mb = 100
  }
}

-- 🔍 Check if auto migration is enabled
---@return boolean
function M.is_enabled()
  return config.enabled and state.enabled
end

-- ⚙️ Configure auto migration
---@param opts AutoMigrationConfig
function M.configure(opts)
  config = vim.tbl_extend("force", config, opts or {})
  state.enabled = config.enabled
end

-- 🔍 Detect if history file needs migration
---@param history_filepath string Path to history JSON file
---@return boolean needs_migration
---@return string | nil error
function M.needs_migration(history_filepath)
  local Path = require("plenary.path")
  local file = Path:new(history_filepath)
  
  if not file:exists() then
    return false, "File does not exist"
  end
  
  local content, read_error = pcall(function()
    return file:read()
  end)
  
  if not content then
    return false, "Failed to read file: " .. tostring(read_error)
  end
  
  local history, decode_error = pcall(function()
    return vim.json.decode(read_error)
  end)
  
  if not history then
    return false, "Failed to decode JSON: " .. tostring(decode_error)
  end
  
  -- 🚨 Use migration engine to detect format
  local migration_engine = Migration.new()
  local version = migration_engine:detect_version(history)
  
  return version == Migration.LEGACY_VERSION, nil
end

-- 📊 Progress callback for migration reporting
---@param progress Migration.MigrationProgress
local function report_progress(progress)
  if not config.progress_reporting then return end
  
  local report = Migration.get_progress_report(progress)
  Utils.info(report)
end

-- ⚡ Perform automatic migration for a single file
---@param history_filepath string
---@param backup_dir string | nil
---@return boolean success
---@return string | nil error
function M.migrate_file(history_filepath, backup_dir)
  local Path = require("plenary.path")
  local file = Path:new(history_filepath)
  
  if not file:exists() then
    return false, "History file does not exist"
  end
  
  -- ⏱️ Start performance monitoring
  local start_time = vim.loop.hrtime()
  local initial_memory = collectgarbage("count")
  
  -- 📖 Load history
  local content = file:read()
  if not content then
    return false, "Failed to read history file"
  end
  
  local success, history = pcall(vim.json.decode, content)
  if not success then
    return false, "Failed to decode history JSON: " .. tostring(history)
  end
  
  -- 🔍 Check if migration is needed
  local migration_engine = Migration.new(backup_dir)
  if migration_engine:is_modern_format(history) then
    Utils.debug("File already in modern format: " .. history_filepath)
    return true, nil
  end
  
  -- 💾 Create backup if enabled
  local backup_path = nil
  if config.backup_enabled then
    backup_path = migration_engine:create_backup(history, file.filename)
    if not backup_path then
      return false, "Failed to create backup"
    end
  end
  
  -- 🔄 Perform migration
  local migrated_history, migration_result = migration_engine:convert_legacy_to_modern(history)
  
  if not migration_result.success then
    -- 🔄 Rollback if backup exists
    if backup_path then
      migration_engine:rollback_from_backup(backup_path, history_filepath)
    end
    return false, migration_result.error or "Migration failed"
  end
  
  -- 🔧 Apply tool state preservation
  migrated_history = Migration.migrate_tool_state_tracking(migrated_history, migration_result)
  
  -- 💾 Save migrated history atomically
  local json_content = vim.json.encode(migrated_history)
  local write_success, write_error = migration_engine:atomic_write(history_filepath, json_content)
  
  if not write_success then
    -- 🔄 Rollback if backup exists
    if backup_path then
      migration_engine:rollback_from_backup(backup_path, history_filepath)
    end
    return false, "Failed to write migrated history: " .. (write_error or "unknown error")
  end
  
  -- ⏱️ Performance monitoring
  local end_time = vim.loop.hrtime()
  local elapsed_ms = (end_time - start_time) / 1000000  -- Convert to ms
  local final_memory = collectgarbage("count")
  local memory_used_mb = (final_memory - initial_memory) / 1024
  
  -- 📊 Update statistics
  state.migration_statistics.files_migrated = state.migration_statistics.files_migrated + 1
  state.migration_statistics.total_entries_converted = state.migration_statistics.total_entries_converted + migration_result.entries_count
  state.migration_statistics.total_messages_generated = state.migration_statistics.total_messages_generated + migration_result.messages_count
  
  -- ⚠️ Check performance targets
  if elapsed_ms > config.performance_targets.max_time_per_file_ms then
    Utils.warn(string.format(
      "Migration exceeded time target: %.2fms (target: %dms) for %s",
      elapsed_ms, config.performance_targets.max_time_per_file_ms, history_filepath
    ))
  end
  
  if memory_used_mb > config.performance_targets.max_memory_usage_mb then
    Utils.warn(string.format(
      "Migration exceeded memory target: %.2fMB (target: %dMB) for %s",
      memory_used_mb, config.performance_targets.max_memory_usage_mb, history_filepath
    ))
  end
  
  Utils.info(string.format(
    "✅ Migration completed: %s (%d entries → %d messages, %.2fms, %.2fMB)",
    file.filename,
    migration_result.entries_count,
    migration_result.messages_count,
    elapsed_ms,
    memory_used_mb
  ))
  
  return true, nil
end

-- 🔄 Auto-migrate all history files for a project
---@param bufnr integer
---@return boolean success
---@return integer files_migrated
---@return integer files_failed
function M.migrate_project_histories(bufnr)
  if state.migration_in_progress then
    Utils.warn("Migration already in progress")
    return false, 0, 0
  end
  
  state.migration_in_progress = true
  
  local History = require("avante.path").history
  local history_dir = History.get_history_dir(bufnr)
  
  -- 📁 Get all history files
  local files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
  
  -- 🚫 Filter out metadata files
  local history_files = {}
  for _, file in ipairs(files) do
    if not file:match("metadata.json") then
      table.insert(history_files, file)
    end
  end
  
  if #history_files == 0 then
    state.migration_in_progress = false
    return true, 0, 0
  end
  
  -- 📊 Initialize progress tracking
  local progress = Migration.create_progress(#history_files)
  local backup_dir = Utils.join_paths(vim.fn.stdpath("data"), "avante", "backups")
  
  Utils.info(string.format("Starting migration of %d history files...", #history_files))
  
  -- 🔄 Process each file
  for _, file_path in ipairs(history_files) do
    local Path = require("plenary.path")
    local file = Path:new(file_path)
    progress.current_file = file.filename
    
    -- 🔍 Check if migration is needed
    local needs_migration, check_error = M.needs_migration(file_path)
    
    if check_error then
      Utils.warn(string.format("Failed to check migration status for %s: %s", file.filename, check_error))
      Migration.update_progress(progress, file.filename, false)
      state.migration_statistics.files_failed = state.migration_statistics.files_failed + 1
      goto continue
    end
    
    if not needs_migration then
      Utils.debug(string.format("File %s does not need migration", file.filename))
      Migration.update_progress(progress, file.filename, true)
      goto continue
    end
    
    -- 🔄 Perform migration
    local success, error = M.migrate_file(file_path, backup_dir)
    Migration.update_progress(progress, file.filename, success)
    
    if not success then
      Utils.error(string.format("Failed to migrate %s: %s", file.filename, error or "unknown error"))
      state.migration_statistics.files_failed = state.migration_statistics.files_failed + 1
    end
    
    -- 📊 Report progress
    report_progress(progress)
    
    ::continue::
  end
  
  state.migration_in_progress = false
  state.last_migration_check = Utils.get_timestamp()
  
  -- 📊 Final statistics
  Utils.info(string.format(
    "Migration completed: %d succeeded, %d failed, %d total entries converted, %d total messages generated",
    progress.completed,
    progress.failed,
    state.migration_statistics.total_entries_converted,
    state.migration_statistics.total_messages_generated
  ))
  
  return progress.failed == 0, progress.completed, progress.failed
end

-- 🚀 Auto-migration hook for history loading
---@param bufnr integer
---@param filename string | nil
---@return boolean migration_occurred
function M.auto_migrate_on_load(bufnr, filename)
  if not M.is_enabled() then
    return false
  end
  
  if state.migration_in_progress then
    return false
  end
  
  local History = require("avante.path").history
  local history_filepath
  
  if filename then
    history_filepath = tostring(History.get_filepath(bufnr, filename))
  else
    history_filepath = tostring(History.get_latest_filepath(bufnr, false))
  end
  
  -- 🔍 Check if specific file needs migration
  local needs_migration, error = M.needs_migration(history_filepath)
  
  if error then
    Utils.debug(string.format("Migration check failed for %s: %s", history_filepath, error))
    return false
  end
  
  if not needs_migration then
    return false
  end
  
  Utils.info(string.format("Auto-migrating history file: %s", history_filepath))
  
  local backup_dir = Utils.join_paths(vim.fn.stdpath("data"), "avante", "backups")
  local success, migrate_error = M.migrate_file(history_filepath, backup_dir)
  
  if not success then
    Utils.error(string.format("Auto-migration failed for %s: %s", history_filepath, migrate_error or "unknown error"))
    return false
  end
  
  return true
end

-- 📊 Get migration statistics
---@return table<string, integer>
function M.get_statistics()
  return vim.deepcopy(state.migration_statistics)
end

-- 🧹 Reset migration statistics
function M.reset_statistics()
  state.migration_statistics = {
    files_migrated = 0,
    files_failed = 0,
    total_entries_converted = 0,
    total_messages_generated = 0
  }
end

-- 🛠️ Manual migration trigger for edge cases
---@param bufnr integer
---@param force boolean Force migration even if files appear modern
---@return boolean success
function M.manual_migration(bufnr, force)
  force = force or false
  
  Utils.info("Starting manual migration" .. (force and " (forced)" or ""))
  
  if not force then
    return M.migrate_project_histories(bufnr)
  end
  
  -- 🔄 Force migration by temporarily disabling format checks
  local original_is_modern_format = Migration.MigrationEngine.is_modern_format
  Migration.MigrationEngine.is_modern_format = function() return false end
  
  local success, migrated, failed = M.migrate_project_histories(bufnr)
  
  -- 🔄 Restore original function
  Migration.MigrationEngine.is_modern_format = original_is_modern_format
  
  return success
end

return M
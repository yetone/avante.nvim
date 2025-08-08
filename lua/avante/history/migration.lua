local Models = require("avante.history.models")
local Utils = require("avante.utils")
local Path = require("plenary.path")

---@class avante.history.migration
local M = {}

---@class avante.MigrationConfig
---@field auto_migrate boolean Whether to automatically migrate on detection
---@field create_backups boolean Whether to create backups before migration
---@field backup_suffix string Suffix for backup files
---@field preserve_legacy boolean Whether to keep legacy files after migration
---@field dry_run boolean Whether to perform a dry run without actual changes
---@field batch_size number Number of files to process in one batch

---@class avante.MigrationResult
---@field success boolean Whether migration was successful
---@field migrated_count number Number of files successfully migrated
---@field failed_count number Number of files that failed to migrate
---@field skipped_count number Number of files skipped (already migrated)
---@field errors string[] List of error messages
---@field warnings string[] List of warning messages
---@field backup_paths string[] List of created backup file paths
---@field duration_ms number Migration duration in milliseconds

---@class avante.MigrationProgress
---@field total_files number Total number of files to migrate
---@field current_file number Current file being processed
---@field completed_files number Number of completed files
---@field current_filename string Name of current file being processed
---@field status "scanning" | "migrating" | "completed" | "failed" Current status

-- 📋 Default migration configuration
M.DEFAULT_CONFIG = {
  auto_migrate = false,
  create_backups = true,
  backup_suffix = ".legacy_backup",
  preserve_legacy = false,
  dry_run = false,
  batch_size = 10,
}

---🔍 Scans directory for files that need migration
---@param directory_path string Path to scan
---@return string[] legacy_files List of files needing migration
---@return string? error_message
function M.scan_for_legacy_files(directory_path)
  local dir = Path:new(directory_path)
  if not dir:exists() or not dir:is_dir() then
    return {}, "Directory does not exist or is not a directory: " .. directory_path
  end
  
  local legacy_files = {}
  
  for file in dir:iterdir() do
    if file:is_file() and file:suffix() == ".json" and file:basename() ~= "metadata.json" then
      local needs_migration, err = M.needs_migration(tostring(file))
      if err then
        Utils.warn("Error checking migration status for", tostring(file), ":", err)
      elseif needs_migration then
        table.insert(legacy_files, tostring(file))
      end
    end
  end
  
  Utils.debug("Found", #legacy_files, "files needing migration in", directory_path)
  return legacy_files, nil
end

---🔍 Checks if a specific file needs migration
---@param file_path string Path to the file
---@return boolean needs_migration
---@return string? error_message
function M.needs_migration(file_path)
  local filepath = Path:new(file_path)
  
  if not filepath:exists() then
    return false, "File does not exist: " .. file_path
  end
  
  -- 📖 Read and parse file
  local read_ok, content = pcall(function()
    return filepath:read()
  end)
  
  if not read_ok or not content or content == "" then
    return false, "Cannot read file or file is empty"
  end
  
  local parse_ok, data = pcall(vim.json.decode, content)
  if not parse_ok then
    return false, "File is not valid JSON"
  end
  
  -- 🔍 Check if it's legacy format
  local is_legacy = Models.is_legacy_format(data)
  Utils.debug("File", file_path, "needs migration:", is_legacy)
  
  return is_legacy, nil
end

---🔄 Creates a backup of the original file
---@param file_path string Original file path
---@param config avante.MigrationConfig Migration configuration
---@return string? backup_path Path to backup file if created
---@return string? error_message
function M.create_backup(file_path, config)
  if not config.create_backups then
    return nil, nil
  end
  
  local original_file = Path:new(file_path)
  if not original_file:exists() then
    return nil, "Original file does not exist: " .. file_path
  end
  
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local backup_name = original_file:basename() .. "." .. timestamp .. config.backup_suffix
  local backup_path = original_file:parent():joinpath(backup_name)
  
  local copy_ok, copy_err = pcall(function()
    original_file:copy({ destination = backup_path })
  end)
  
  if not copy_ok then
    return nil, "Failed to create backup: " .. (copy_err or "unknown error")
  end
  
  Utils.debug("Created backup at", tostring(backup_path))
  return tostring(backup_path), nil
end

---🔄 Migrates a single file from legacy to unified format
---@param file_path string Path to the file to migrate
---@param config avante.MigrationConfig Migration configuration
---@return boolean success
---@return string? error_message
---@return string? backup_path
function M.migrate_file(file_path, config)
  local filepath = Path:new(file_path)
  
  -- 🔍 Check if migration is needed
  local needs_migration, check_err = M.needs_migration(file_path)
  if check_err then
    return false, "Migration check failed: " .. check_err, nil
  end
  
  if not needs_migration then
    Utils.debug("File", file_path, "does not need migration")
    return true, nil, nil
  end
  
  -- 📖 Load legacy format
  local read_ok, content = pcall(function()
    return filepath:read()
  end)
  
  if not read_ok or not content then
    return false, "Failed to read file: " .. (content or "unknown error"), nil
  end
  
  local parse_ok, legacy_data = pcall(vim.json.decode, content)
  if not parse_ok then
    return false, "Failed to parse JSON: " .. (legacy_data or "invalid JSON"), nil
  end
  
  -- 🔄 Create backup if enabled
  local backup_path, backup_err = M.create_backup(file_path, config)
  if backup_err then
    Utils.warn("Backup creation failed, proceeding anyway:", backup_err)
  end
  
  -- 🏗️ Perform migration
  local unified_history = Models.migrate_from_legacy(legacy_data)
  
  -- 📝 Add migration metadata
  unified_history.metadata.migration_info = {
    migrated_at = Utils.get_timestamp(),
    original_format = legacy_data.entries and "ChatHistoryEntry" or "PartialUnified",
    migration_engine_version = M.VERSION or "1.0.0",
    backup_created = backup_path ~= nil,
    backup_path = backup_path,
  }
  
  -- 💾 Save migrated version (dry run check)
  if config.dry_run then
    Utils.debug("DRY RUN: Would migrate", file_path)
    return true, nil, backup_path
  end
  
  local save_ok, save_content = pcall(vim.json.encode, unified_history)
  if not save_ok then
    return false, "Failed to serialize migrated data: " .. (save_content or "unknown error"), backup_path
  end
  
  local write_ok, write_err = pcall(function()
    filepath:write(save_content, "w")
  end)
  
  if not write_ok then
    return false, "Failed to write migrated file: " .. (write_err or "unknown error"), backup_path
  end
  
  Utils.debug("Successfully migrated", file_path)
  return true, nil, backup_path
end

---🚀 Migrates multiple files in a directory
---@param directory_path string Directory containing files to migrate
---@param config? avante.MigrationConfig Migration configuration
---@param progress_callback? fun(progress: avante.MigrationProgress): nil Progress callback
---@return avante.MigrationResult
function M.migrate_directory(directory_path, config, progress_callback)
  config = vim.tbl_extend("force", M.DEFAULT_CONFIG, config or {})
  
  local start_time = vim.uv.hrtime()
  
  ---@type avante.MigrationResult
  local result = {
    success = false,
    migrated_count = 0,
    failed_count = 0,
    skipped_count = 0,
    errors = {},
    warnings = {},
    backup_paths = {},
    duration_ms = 0,
  }
  
  -- 🔍 Scan for legacy files
  if progress_callback then
    progress_callback({
      total_files = 0,
      current_file = 0,
      completed_files = 0,
      current_filename = "",
      status = "scanning",
    })
  end
  
  local legacy_files, scan_err = M.scan_for_legacy_files(directory_path)
  if scan_err then
    table.insert(result.errors, "Scan failed: " .. scan_err)
    return result
  end
  
  if #legacy_files == 0 then
    Utils.debug("No files need migration in", directory_path)
    result.success = true
    result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
    return result
  end
  
  -- 🔄 Process files in batches
  local total_files = #legacy_files
  
  for i = 1, total_files, config.batch_size do
    local batch_end = math.min(i + config.batch_size - 1, total_files)
    
    for j = i, batch_end do
      local file_path = legacy_files[j]
      local filename = Path:new(file_path):basename()
      
      if progress_callback then
        progress_callback({
          total_files = total_files,
          current_file = j,
          completed_files = j - 1,
          current_filename = filename,
          status = "migrating",
        })
      end
      
      -- 🔄 Migrate individual file
      local success, error_msg, backup_path = M.migrate_file(file_path, config)
      
      if success then
        result.migrated_count = result.migrated_count + 1
        if backup_path then
          table.insert(result.backup_paths, backup_path)
        end
        Utils.debug("Migrated", filename)
      else
        result.failed_count = result.failed_count + 1
        local error_message = string.format("Failed to migrate %s: %s", filename, error_msg or "unknown error")
        table.insert(result.errors, error_message)
        Utils.warn(error_message)
      end
      
      -- 🛡️ Remove legacy file if requested and migration succeeded
      if success and not config.preserve_legacy and not config.dry_run then
        local legacy_file = Path:new(file_path)
        if backup_path then -- Only remove if backup was created
          local remove_ok, remove_err = pcall(function()
            legacy_file:rm()
          end)
          if not remove_ok then
            table.insert(result.warnings, "Failed to remove legacy file " .. file_path .. ": " .. (remove_err or "unknown error"))
          end
        end
      end
    end
    
    -- 🎯 Small delay between batches to avoid overwhelming system
    if batch_end < total_files then
      vim.defer_fn(function() end, 10)
    end
  end
  
  result.success = result.failed_count == 0
  result.duration_ms = (vim.uv.hrtime() - start_time) / 1000000
  
  if progress_callback then
    progress_callback({
      total_files = total_files,
      current_file = total_files,
      completed_files = total_files,
      current_filename = "",
      status = result.success and "completed" or "failed",
    })
  end
  
  Utils.debug("Migration completed:", 
             "success=" .. tostring(result.success),
             "migrated=" .. result.migrated_count,
             "failed=" .. result.failed_count,
             "duration=" .. string.format("%.2fms", result.duration_ms))
  
  return result
end

---🔄 Performs automatic migration check and execution
---@param directory_path string Directory to check and migrate
---@param config? avante.MigrationConfig Migration configuration
---@return boolean migration_performed Whether migration was performed
---@return avante.MigrationResult? result Migration result if performed
function M.auto_migrate_if_needed(directory_path, config)
  config = vim.tbl_extend("force", M.DEFAULT_CONFIG, config or {})
  
  if not config.auto_migrate then
    return false, nil
  end
  
  -- 🔍 Quick check if any migration is needed
  local legacy_files, scan_err = M.scan_for_legacy_files(directory_path)
  if scan_err or #legacy_files == 0 then
    return false, nil
  end
  
  Utils.info("Auto-migration triggered for", #legacy_files, "files in", directory_path)
  
  local result = M.migrate_directory(directory_path, config)
  
  if result.success then
    Utils.info("Auto-migration completed successfully:",
               result.migrated_count, "files migrated")
  else
    Utils.error("Auto-migration failed:",
                result.failed_count, "failures,",
                #result.errors, "errors")
  end
  
  return true, result
end

---🔍 Validates migration results by comparing data integrity
---@param original_path string Path to original file
---@param migrated_path string Path to migrated file
---@return boolean valid
---@return string[] issues List of validation issues found
function M.validate_migration(original_path, migrated_path)
  local issues = {}
  
  -- 📖 Load both versions
  local orig_file = Path:new(original_path)
  local migr_file = Path:new(migrated_path)
  
  if not orig_file:exists() then
    table.insert(issues, "Original file does not exist")
    return false, issues
  end
  
  if not migr_file:exists() then
    table.insert(issues, "Migrated file does not exist")
    return false, issues
  end
  
  local orig_ok, orig_content = pcall(function()
    return vim.json.decode(orig_file:read())
  end)
  
  local migr_ok, migr_content = pcall(function()
    return vim.json.decode(migr_file:read())
  end)
  
  if not orig_ok then
    table.insert(issues, "Cannot parse original file")
    return false, issues
  end
  
  if not migr_ok then
    table.insert(issues, "Cannot parse migrated file")
    return false, issues
  end
  
  -- 🔍 Validate content preservation
  if orig_content.entries then
    local expected_messages = #orig_content.entries * 2 -- Rough estimate
    local actual_messages = #migr_content.messages
    
    if math.abs(expected_messages - actual_messages) > #orig_content.entries then
      table.insert(issues, string.format("Message count mismatch: expected ~%d, got %d", 
                                         expected_messages, actual_messages))
    end
  end
  
  -- 🔍 Validate schema version
  if not migr_content.schema_version then
    table.insert(issues, "Missing schema version in migrated file")
  end
  
  -- 🔍 Validate UUID preservation
  if orig_content.uuid and migr_content.uuid ~= orig_content.uuid then
    table.insert(issues, "UUID mismatch between original and migrated")
  end
  
  return #issues == 0, issues
end

---🔄 Rolls back a migration using backup files
---@param migrated_file_path string Path to the migrated file
---@param backup_path string Path to the backup file
---@return boolean success
---@return string? error_message
function M.rollback_migration(migrated_file_path, backup_path)
  local migrated_file = Path:new(migrated_file_path)
  local backup_file = Path:new(backup_path)
  
  if not backup_file:exists() then
    return false, "Backup file does not exist: " .. backup_path
  end
  
  -- 🔄 Restore from backup
  local restore_ok, restore_err = pcall(function()
    backup_file:copy({ destination = migrated_file })
  end)
  
  if not restore_ok then
    return false, "Failed to restore from backup: " .. (restore_err or "unknown error")
  end
  
  Utils.debug("Rolled back migration for", migrated_file_path, "from backup", backup_path)
  return true, nil
end

---📊 Generates migration report
---@param result avante.MigrationResult
---@return string report Human-readable migration report
function M.generate_report(result)
  local lines = {
    "🔄 History Migration Report",
    "========================",
    "",
    string.format("📊 Summary: %s", result.success and "✅ Success" or "❌ Failed"),
    string.format("📁 Files migrated: %d", result.migrated_count),
    string.format("❌ Files failed: %d", result.failed_count),
    string.format("⏱️  Duration: %.2f ms", result.duration_ms),
    "",
  }
  
  if #result.backup_paths > 0 then
    table.insert(lines, "💾 Backup files created:")
    for _, backup_path in ipairs(result.backup_paths) do
      table.insert(lines, "   • " .. backup_path)
    end
    table.insert(lines, "")
  end
  
  if #result.errors > 0 then
    table.insert(lines, "❌ Errors:")
    for _, error in ipairs(result.errors) do
      table.insert(lines, "   • " .. error)
    end
    table.insert(lines, "")
  end
  
  if #result.warnings > 0 then
    table.insert(lines, "⚠️  Warnings:")
    for _, warning in ipairs(result.warnings) do
      table.insert(lines, "   • " .. warning)
    end
    table.insert(lines, "")
  end
  
  table.insert(lines, "🎯 Migration engine version: " .. (M.VERSION or "1.0.0"))
  
  return table.concat(lines, "\n")
end

-- 📋 Version identifier for tracking migration engine changes
M.VERSION = "1.0.0"

return M
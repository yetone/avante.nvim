---🔄 Migration Engine for Avante history storage
---Handles conversion from legacy ChatHistoryEntry format to UnifiedHistoryMessage format

local Models = require("avante.history.storage.models")
local Utils = require("avante.utils")
local Path = require("avante.path")

local M = {}

---@class avante.storage.MigrationEngine
---@field config table Migration configuration
local MigrationEngine = {}
MigrationEngine.__index = MigrationEngine

---🏗️ Create new migration engine instance
---@param config? table Migration configuration
---@return avante.storage.MigrationEngine
function M.new(config)
  config = config or {}
  
  local default_config = {
    backup_enabled = config.backup_enabled ~= false,
    backup_suffix = config.backup_suffix or "_backup_" .. os.date("%Y%m%d_%H%M%S"),
    chunk_size = config.chunk_size or 50, -- 📦 Process migrations in chunks to avoid memory issues
    progress_callback = config.progress_callback, -- 📊 Progress reporting callback
    dry_run = config.dry_run or false, -- 🧪 Test migration without making changes
    preserve_timestamps = config.preserve_timestamps ~= false,
    validate_after_migration = config.validate_after_migration ~= false,
  }
  
  local instance = {
    config = default_config,
    _migration_logs = {}, -- 📝 Track migration operations
  }
  
  return setmetatable(instance, MigrationEngine)
end

---📝 Log migration operation
---@param level string Log level ("info", "warn", "error")
---@param message string Log message
---@param details? table Additional details
function MigrationEngine:_log(level, message, details)
  local log_entry = {
    timestamp = Utils.get_timestamp(),
    level = level,
    message = message,
    details = details,
  }
  
  table.insert(self._migration_logs, log_entry)
  
  -- 🖥️ Also output to console
  if level == "error" then
    Utils.error("Migration: " .. message)
  elseif level == "warn" then
    Utils.warn("Migration: " .. message)
  else
    Utils.debug("Migration: " .. message)
  end
end

---📊 Report migration progress
---@param current number Current item being processed
---@param total number Total items to process
---@param operation string Current operation description
function MigrationEngine:_report_progress(current, total, operation)
  if self.config.progress_callback then
    local progress = {
      current = current,
      total = total,
      percentage = math.floor((current / total) * 100),
      operation = operation,
    }
    self.config.progress_callback(progress)
  else
    -- 📊 Simple console progress
    local percentage = math.floor((current / total) * 100)
    Utils.debug(string.format("Migration progress: %d%% (%d/%d) - %s", percentage, current, total, operation))
  end
end

---🔍 Detect legacy history format in project directory
---@param project_path string Path to project directory
---@return boolean has_legacy_format
---@return table? legacy_files List of legacy history files found
---@return string? error_message
function MigrationEngine:detect_legacy_format(project_path)
  local history_path = Utils.join_paths(project_path, "history")
  
  if vim.fn.isdirectory(history_path) == 0 then
    return false, nil, nil -- 📁 No history directory
  end
  
  local legacy_files = {}
  local has_metadata = false
  
  -- 🔍 Scan history directory
  for item in vim.fs.dir(history_path) do
    local item_path = Utils.join_paths(history_path, item)
    
    if item == "metadata.json" then
      has_metadata = true
      
      -- 📖 Check if metadata indicates legacy format
      local file = io.open(item_path, "r")
      if file then
        local content = file:read("*all")
        file:close()
        
        if content and content ~= "" then
          local success, metadata = pcall(vim.json.decode, content)
          if success and metadata.version == Models.SCHEMA_VERSION then
            return false, nil, nil -- 📅 Already migrated
          end
        end
      end
    elseif string.match(item, "%.json$") and item ~= "metadata.json" then
      -- 📄 Check if this is a legacy history file
      local file = io.open(item_path, "r")
      if file then
        local content = file:read("*all")
        file:close()
        
        if content and content ~= "" then
          local success, history_data = pcall(vim.json.decode, content)
          if success then
            -- 🔍 Detect legacy format by checking for "entries" field
            if history_data.entries and not history_data.version then
              table.insert(legacy_files, {
                file = item,
                path = item_path,
                type = "legacy_entries",
              })
            elseif history_data.messages and not history_data.version then
              table.insert(legacy_files, {
                file = item,
                path = item_path,
                type = "legacy_messages",
              })
            end
          end
        end
      end
    end
  end
  
  return #legacy_files > 0, legacy_files, nil
end

---💾 Create backup of project history
---@param project_path string Path to project directory
---@param backup_path? string Optional custom backup path
---@return boolean success
---@return string? backup_location
---@return string? error_message
function MigrationEngine:create_backup(project_path, backup_path)
  if not self.config.backup_enabled then
    self:_log("info", "Backup disabled, skipping backup creation")
    return true, nil, nil
  end
  
  local history_path = Utils.join_paths(project_path, "history")
  if vim.fn.isdirectory(history_path) == 0 then
    return true, nil, "No history directory to backup" -- 📁 Nothing to backup
  end
  
  -- 📁 Determine backup location
  if not backup_path then
    backup_path = history_path .. self.config.backup_suffix
  end
  
  self:_log("info", "Creating backup", { source = history_path, destination = backup_path })
  
  -- 📦 Copy entire history directory
  local success, error = Path.copy_dir(history_path, backup_path)
  if not success then
    self:_log("error", "Failed to create backup", { error = error })
    return false, nil, "Failed to create backup: " .. (error or "unknown error")
  end
  
  self:_log("info", "Backup created successfully", { location = backup_path })
  return true, backup_path, nil
end

---🔄 Migrate a single legacy history file
---@param legacy_file table Legacy file information
---@param project_name string Project name
---@return boolean success
---@return avante.storage.UnifiedChatHistory? migrated_history
---@return string? error_message
function MigrationEngine:migrate_legacy_file(legacy_file, project_name)
  self:_log("info", "Migrating legacy file", { file = legacy_file.file, type = legacy_file.type })
  
  -- 📖 Read legacy file
  local file = io.open(legacy_file.path, "r")
  if not file then
    return false, nil, "Failed to open legacy file: " .. legacy_file.path
  end
  
  local content = file:read("*all")
  file:close()
  
  if not content or content == "" then
    return false, nil, "Legacy file is empty"
  end
  
  -- 🔄 Parse legacy format
  local success, legacy_data = pcall(vim.json.decode, content)
  if not success then
    return false, nil, "Failed to parse legacy JSON: " .. (legacy_data or "unknown error")
  end
  
  -- 🔄 Convert based on legacy type
  local unified_history
  if legacy_file.type == "legacy_entries" then
    unified_history = Models.convert_legacy_history(legacy_data, project_name)
  elseif legacy_file.type == "legacy_messages" then
    -- 🔄 Handle partial migration case (messages array exists but no version)
    unified_history = Models.convert_legacy_history(legacy_data, project_name)
  else
    return false, nil, "Unknown legacy format type: " .. legacy_file.type
  end
  
  -- ✅ Validate migrated history
  if self.config.validate_after_migration then
    local is_valid, error_msg = Models.validate_unified_history(unified_history)
    if not is_valid then
      return false, nil, "Migrated history validation failed: " .. error_msg
    end
  end
  
  self:_log("info", "Successfully migrated legacy file", {
    file = legacy_file.file,
    message_count = #unified_history.messages,
  })
  
  return true, unified_history, nil
end

---🔄 Perform complete migration for a project
---@param project_name string Project to migrate
---@param storage_engine table Storage engine to save migrated data
---@return boolean success
---@return table migration_summary
---@return string? error_message
function MigrationEngine:migrate_project(project_name, storage_engine)
  local project_path = Utils.join_paths(vim.fn.stdpath("state"), "avante", "projects", project_name)
  
  self:_log("info", "Starting migration for project", { project = project_name, path = project_path })
  
  -- 🔍 Detect legacy format
  local has_legacy, legacy_files, detect_error = self:detect_legacy_format(project_path)
  if detect_error then
    return false, {}, "Failed to detect legacy format: " .. detect_error
  end
  
  if not has_legacy then
    self:_log("info", "No migration needed for project", { project = project_name })
    return true, { migrated_count = 0, skipped_reason = "no_legacy_format" }, nil
  end
  
  -- 💾 Create backup if not in dry run mode
  local backup_location
  if not self.config.dry_run then
    local backup_success, backup_loc, backup_error = self:create_backup(project_path)
    if not backup_success then
      return false, {}, backup_error or "Failed to create backup"
    end
    backup_location = backup_loc
  end
  
  -- 🔄 Process legacy files in chunks
  local migration_summary = {
    total_files = #legacy_files,
    migrated_count = 0,
    failed_count = 0,
    errors = {},
    backup_location = backup_location,
    started_at = Utils.get_timestamp(),
  }
  
  for i, legacy_file in ipairs(legacy_files) do
    self:_report_progress(i, #legacy_files, "Migrating " .. legacy_file.file)
    
    local migrate_success, migrated_history, migrate_error = self:migrate_legacy_file(legacy_file, project_name)
    if migrate_success and migrated_history then
      -- 💾 Save migrated history using storage engine
      if not self.config.dry_run then
        local save_success, save_error = storage_engine:save(migrated_history, project_name)
        if save_success then
          migration_summary.migrated_count = migration_summary.migrated_count + 1
          
          -- 🗑️ Remove legacy file after successful migration
          local remove_success, remove_error = os.remove(legacy_file.path)
          if not remove_success then
            self:_log("warn", "Failed to remove legacy file after migration", {
              file = legacy_file.file,
              error = remove_error,
            })
          end
        else
          migration_summary.failed_count = migration_summary.failed_count + 1
          table.insert(migration_summary.errors, {
            file = legacy_file.file,
            error = "Failed to save migrated history: " .. (save_error or "unknown error"),
          })
        end
      else
        -- 🧪 Dry run - just count as success
        migration_summary.migrated_count = migration_summary.migrated_count + 1
      end
    else
      migration_summary.failed_count = migration_summary.failed_count + 1
      table.insert(migration_summary.errors, {
        file = legacy_file.file,
        error = migrate_error or "Unknown migration error",
      })
    end
  end
  
  migration_summary.completed_at = Utils.get_timestamp()
  
  self:_log("info", "Migration completed", migration_summary)
  
  local overall_success = migration_summary.failed_count == 0
  return overall_success, migration_summary, nil
end

---🔄 Batch migrate multiple projects
---@param project_names string[] List of project names to migrate
---@param storage_engine table Storage engine to use
---@return table batch_results Results for each project migration
function MigrationEngine:batch_migrate_projects(project_names, storage_engine)
  local batch_results = {
    total_projects = #project_names,
    successful_projects = 0,
    failed_projects = 0,
    project_results = {},
    started_at = Utils.get_timestamp(),
  }
  
  for i, project_name in ipairs(project_names) do
    self:_report_progress(i, #project_names, "Migrating project " .. project_name)
    
    local success, summary, error = self:migrate_project(project_name, storage_engine)
    batch_results.project_results[project_name] = {
      success = success,
      summary = summary,
      error = error,
    }
    
    if success then
      batch_results.successful_projects = batch_results.successful_projects + 1
    else
      batch_results.failed_projects = batch_results.failed_projects + 1
    end
  end
  
  batch_results.completed_at = Utils.get_timestamp()
  return batch_results
end

---🔍 Auto-discover projects that need migration
---@param base_path string Base path to scan for projects
---@return string[] project_names List of projects needing migration
function MigrationEngine:discover_projects_needing_migration(base_path)
  local projects = {}
  
  if vim.fn.isdirectory(base_path) == 0 then
    return projects
  end
  
  -- 🔍 Scan all subdirectories for projects
  for item in vim.fs.dir(base_path) do
    local item_path = Utils.join_paths(base_path, item)
    if vim.fn.isdirectory(item_path) == 1 then
      local has_legacy, _, _ = self:detect_legacy_format(item_path)
      if has_legacy then
        table.insert(projects, item)
      end
    end
  end
  
  return projects
end

---📊 Get migration logs
---@return table[] logs List of migration log entries
function MigrationEngine:get_logs()
  return vim.deepcopy(self._migration_logs)
end

---🧹 Clear migration logs
function MigrationEngine:clear_logs()
  self._migration_logs = {}
end

---✅ Validate project after migration
---@param project_name string
---@param storage_engine table
---@return boolean is_valid
---@return table validation_results
function MigrationEngine:validate_migrated_project(project_name, storage_engine)
  local validation_results = {
    total_histories = 0,
    valid_histories = 0,
    invalid_histories = 0,
    errors = {},
  }
  
  -- 📋 List all histories for the project
  local histories, list_error = storage_engine:list(project_name)
  if list_error then
    validation_results.errors.list_error = list_error
    return false, validation_results
  end
  
  validation_results.total_histories = #histories
  
  -- ✅ Validate each history
  for _, history_info in ipairs(histories) do
    local history, load_error = storage_engine:load(history_info.uuid, project_name)
    if load_error then
      validation_results.invalid_histories = validation_results.invalid_histories + 1
      table.insert(validation_results.errors, {
        history_id = history_info.uuid,
        error = "Load failed: " .. load_error,
      })
    else
      local is_valid, error_msg = Models.validate_unified_history(history)
      if is_valid then
        validation_results.valid_histories = validation_results.valid_histories + 1
      else
        validation_results.invalid_histories = validation_results.invalid_histories + 1
        table.insert(validation_results.errors, {
          history_id = history_info.uuid,
          error = "Validation failed: " .. error_msg,
        })
      end
    end
  end
  
  return validation_results.invalid_histories == 0, validation_results
end

return M
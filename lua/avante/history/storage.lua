local Utils = require("avante.utils")
local Migration = require("avante.history.migration")
local Path = require("plenary.path")

---@class avante.storage.Engine
local Storage = {}

---Atomic write operation with rollback capability
---@param filepath Path
---@param data table
---@param backup_path Path | nil
---@return boolean success, string | nil error
function Storage.atomic_write(filepath, data, backup_path)
  local temp_path = Path:new(tostring(filepath) .. ".tmp")
  local json_content = vim.json.encode(data)
  
  -- Validate JSON before writing
  local parse_test = pcall(vim.json.decode, json_content)
  if not parse_test then
    return false, "JSON serialization validation failed"
  end
  
  -- Create backup if requested
  if backup_path and filepath:exists() then
    local backup_ok, backup_err = pcall(function()
      filepath:copy({ destination = backup_path })
    end)
    if not backup_ok then
      return false, "Failed to create backup: " .. tostring(backup_err)
    end
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

---Load history with format detection and automatic migration
---@param bufnr integer
---@param filename string | nil
---@param options table | nil Options: { auto_migrate: boolean, backup: boolean, validate: boolean }
---@return avante.UnifiedChatHistory | avante.ChatHistory history, boolean is_migrated
function Storage.load_with_migration(bufnr, filename, options)
  options = options or { auto_migrate = true, backup = true, validate = true }
  
  local history_path = require("avante.path").history
  local history_filepath = filename and history_path.get_filepath(bufnr, filename)
    or history_path.get_latest_filepath(bufnr, false)
    
  if not history_filepath:exists() then
    return history_path.new(bufnr), false
  end
  
  local content = history_filepath:read()
  if not content then
    return history_path.new(bufnr), false
  end
  
  local ok, raw_history = pcall(vim.json.decode, content)
  if not ok then
    Utils.warn("Invalid JSON in history file: " .. tostring(history_filepath))
    return history_path.new(bufnr), false
  end
  
  -- Detect format and migrate if necessary
  local is_legacy, format_type = Migration.detect_format(raw_history)
  
  if is_legacy and options.auto_migrate then
    Utils.info("Migrating legacy format: " .. tostring(history_filepath))
    
    local backup_path = options.backup and 
      Path:new(tostring(history_filepath) .. ".legacy_backup") or nil
    
    local unified_history, errors = Migration.convert_legacy_format(raw_history)
    
    if #errors > 0 then
      Utils.warn("Migration warnings: " .. table.concat(errors, ", "))
    end
    
    if options.validate then
      local is_valid, validation_errors = Migration.validate_unified_history(unified_history)
      if not is_valid then
        Utils.error("Migration validation failed: " .. table.concat(validation_errors, ", "))
        return raw_history, false
      end
    end
    
    -- Save migrated format atomically
    local write_success, write_error = Storage.atomic_write(history_filepath, unified_history, backup_path)
    
    if not write_success then
      Utils.error("Failed to save migrated history: " .. tostring(write_error))
      return raw_history, false
    end
    
    -- Update filename field
    local function filepath_to_filename(fp)
      return tostring(fp):sub(tostring(fp:parent()):len() + 2)
    end
    unified_history.filename = filepath_to_filename(history_filepath)
    
    return unified_history, true
  end
  
  -- Already in unified or modern format, just add filename
  if format_type == "unified" then
    local function filepath_to_filename(fp)
      return tostring(fp):sub(tostring(fp:parent()):len() + 2)
    end
    raw_history.filename = filepath_to_filename(history_filepath)
    return raw_history, false
  end
  
  -- Modern format - return as-is with filename
  local function filepath_to_filename(fp)
    return tostring(fp):sub(tostring(fp:parent()):len() + 2)
  end
  raw_history.filename = filepath_to_filename(history_filepath)
  return raw_history, false
end

---Enhanced save function with unified format support
---@param bufnr integer
---@param history avante.UnifiedChatHistory | avante.ChatHistory
---@param options table | nil Options: { atomic: boolean, compress: boolean, validate: boolean }
---@return boolean success, string | nil error_message
function Storage.save_v2(bufnr, history, options)
  options = options or { atomic = true, compress = false, validate = true }
  
  local history_path = require("avante.path").history
  local history_filepath = history_path.get_filepath(bufnr, history.filename)
  
  -- Ensure this is unified format before saving
  if not history.version or history.version ~= "2.0" then
    -- Auto-convert to unified format
    if history.entries and not history.messages then
      Utils.info("Auto-converting to unified format during save")
      local unified_history, errors = Migration.convert_legacy_format(history)
      if #errors > 0 then
        return false, "Conversion errors during save: " .. table.concat(errors, ", ")
      end
      history = unified_history
    else
      -- Add version to modern format
      history.version = "2.0"
      if not history.migration_metadata then
        history.migration_metadata = {
          original_format = "Modern",
          migration_timestamp = Utils.get_timestamp()
        }
      end
    end
  end
  
  -- Validation
  if options.validate then
    local is_valid, validation_errors = Migration.validate_unified_history(history)
    if not is_valid then
      return false, "Validation errors: " .. table.concat(validation_errors, ", ")
    end
  end
  
  -- Save using atomic write if requested
  if options.atomic then
    local backup_path = Path:new(tostring(history_filepath) .. ".backup")
    local success, error_msg = Storage.atomic_write(history_filepath, history, backup_path)
    if success then
      -- Update metadata
      history_path.save_latest_filename(bufnr, history.filename)
      -- Clean up backup after successful write
      if backup_path:exists() then
        backup_path:rm()
      end
    end
    return success, error_msg
  else
    -- Use original save method
    history_path.save(bufnr, history)
    return true, nil
  end
end

---Batch migration utility function
---@param bufnr integer
---@param progress_callback function | nil
---@return table migration_results
function Storage.migrate_project(bufnr, progress_callback)
  return Migration.batch_migrate(bufnr, progress_callback)
end

---Validate migration results
---@param bufnr integer
---@return table validation_results
function Storage.validate_migration(bufnr)
  local history_path = require("avante.path").history
  local history_dir = history_path.get_history_dir(bufnr)
  local validation_results = {
    total_files = 0,
    valid_unified = 0,
    invalid_files = 0,
    legacy_remaining = 0,
    errors = {}
  }
  
  if not history_dir:exists() then
    return validation_results
  end
  
  local pattern = tostring(history_dir:joinpath("*.json"))
  local files = vim.fn.glob(pattern, true, true)
  
  for _, filepath_str in ipairs(files) do
    if not filepath_str:match("metadata%.json$") then
      validation_results.total_files = validation_results.total_files + 1
      local filepath = Path:new(filepath_str)
      local content = filepath:read()
      
      if content then
        local ok, raw_history = pcall(vim.json.decode, content)
        if ok then
          local is_legacy, format_type = Migration.detect_format(raw_history)
          if is_legacy then
            validation_results.legacy_remaining = validation_results.legacy_remaining + 1
          elseif format_type == "unified" then
            local is_valid, _ = Migration.validate_unified_history(raw_history)
            if is_valid then
              validation_results.valid_unified = validation_results.valid_unified + 1
            else
              validation_results.invalid_files = validation_results.invalid_files + 1
              validation_results.errors[filepath_str] = "Invalid unified format"
            end
          end
        else
          validation_results.invalid_files = validation_results.invalid_files + 1
          validation_results.errors[filepath_str] = "Invalid JSON"
        end
      else
        validation_results.invalid_files = validation_results.invalid_files + 1
        validation_results.errors[filepath_str] = "Could not read file"
      end
    end
  end
  
  return validation_results
end

---Rollback migration for entire project
---@param bufnr integer
---@return table rollback_results
function Storage.rollback_migration(bufnr)
  local history_path = require("avante.path").history
  local history_dir = history_path.get_history_dir(bufnr)
  local rollback_results = {
    total_backups_found = 0,
    successful_rollbacks = 0,
    failed_rollbacks = 0,
    errors = {}
  }
  
  if not history_dir:exists() then
    return rollback_results
  end
  
  local pattern = tostring(history_dir:joinpath("*.legacy_backup"))
  local backup_files = vim.fn.glob(pattern, true, true)
  
  for _, backup_filepath_str in ipairs(backup_files) do
    rollback_results.total_backups_found = rollback_results.total_backups_found + 1
    local backup_filepath = Path:new(backup_filepath_str)
    local original_filepath = Path:new(backup_filepath_str:gsub("%.legacy_backup$", ""))
    
    local success, error_msg = Migration.rollback_migration(original_filepath, backup_filepath)
    if success then
      rollback_results.successful_rollbacks = rollback_results.successful_rollbacks + 1
    else
      rollback_results.failed_rollbacks = rollback_results.failed_rollbacks + 1
      rollback_results.errors[tostring(original_filepath)] = error_msg
    end
  end
  
  return rollback_results
end

---Get performance stats for storage operations
---@return table stats
function Storage.get_performance_stats()
  -- This would be enhanced with actual metrics collection in a real implementation
  return {
    load_time_ms = 0,
    save_time_ms = 0,
    memory_usage_kb = 0,
    migration_count = 0
  }
end

---Validate all history files in project
---@param bufnr integer
---@return table validation_summary
function Storage.validate_all_files(bufnr)
  local validation_results = Storage.validate_migration(bufnr)
  local summary = {
    total_files = validation_results.total_files,
    health_status = "healthy",
    issues = {}
  }
  
  if validation_results.invalid_files > 0 then
    summary.health_status = "unhealthy"
    table.insert(summary.issues, string.format("%d files with errors", validation_results.invalid_files))
  end
  
  if validation_results.legacy_remaining > 0 then
    summary.health_status = validation_results.legacy_remaining == validation_results.total_files 
      and "legacy" or "mixed"
    table.insert(summary.issues, string.format("%d files still in legacy format", validation_results.legacy_remaining))
  end
  
  summary.errors = validation_results.errors
  
  return summary
end

return Storage
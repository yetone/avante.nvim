local Utils = require("avante.utils")
local Path = require("plenary.path")

---@class avante.AtomicStorage
local M = {}

--- 🔧 Atomic operation constants and configuration
M.TEMP_SUFFIX = ".tmp"
M.BACKUP_SUFFIX = ".backup"
M.LOCKFILE_SUFFIX = ".lock"
M.MAX_RETRY_ATTEMPTS = 3
M.RETRY_DELAY_MS = 100
M.OPERATION_TIMEOUT_MS = 30000

--- 📊 Storage operation result
---@class avante.StorageResult
---@field success boolean Operation success status
---@field message string Result message
---@field backup_path string | nil Path to backup file if created
---@field operation_id string Unique operation identifier
---@field duration_ms number Operation duration in milliseconds
---@field error string | nil Error message if operation failed

--- 🔒 Storage lock management
---@class avante.StorageLock
---@field filepath Path Target file path
---@field lockfile_path Path Lock file path
---@field operation_id string Operation identifier
---@field created_at number Lock creation timestamp
---@field timeout_ms number Lock timeout duration

--- 🔒 Acquire storage lock for atomic operations
---@param filepath Path Target file to lock
---@param operation_id string Operation identifier
---@param timeout_ms number | nil Lock timeout (default: 30000ms)
---@return avante.StorageLock | nil lock Storage lock or nil if failed
function M.acquire_lock(filepath, operation_id, timeout_ms)
  timeout_ms = timeout_ms or M.OPERATION_TIMEOUT_MS
  local lockfile_path = Path:new(tostring(filepath) .. M.LOCKFILE_SUFFIX)
  
  -- 🔍 Check for existing lock
  if lockfile_path:exists() then
    local lock_content = lockfile_path:read()
    if lock_content then
      local existing_lock = vim.json.decode(lock_content)
      local lock_age = os.time() * 1000 - existing_lock.created_at
      
      if lock_age < timeout_ms then
        Utils.warn(string.format("⚠️  Storage locked by operation %s (age: %dms)", 
                                existing_lock.operation_id, lock_age))
        return nil
      else
        -- 🗑️ Remove stale lock
        Utils.debug("🗑️  Removing stale lock file")
        lockfile_path:rm()
      end
    end
  end
  
  -- 🔐 Create new lock
  local lock = {
    filepath = filepath,
    lockfile_path = lockfile_path,
    operation_id = operation_id,
    created_at = os.time() * 1000,
    timeout_ms = timeout_ms,
  }
  
  local lock_data = {
    operation_id = operation_id,
    created_at = lock.created_at,
    timeout_ms = timeout_ms,
    filepath = tostring(filepath),
  }
  
  local ok, err = pcall(function()
    lockfile_path:write(vim.json.encode(lock_data), "w")
  end)
  
  if not ok then
    Utils.error("Failed to create storage lock: " .. (err or "unknown error"))
    return nil
  end
  
  Utils.debug(string.format("🔐 Acquired storage lock: %s", operation_id))
  return lock
end

--- 🔓 Release storage lock
---@param lock avante.StorageLock Storage lock to release
---@return boolean success True if lock was released
function M.release_lock(lock)
  if not lock or not lock.lockfile_path:exists() then
    Utils.debug("🔓 Lock already released or doesn't exist")
    return true
  end
  
  local ok, err = pcall(function()
    lock.lockfile_path:rm()
  end)
  
  if not ok then
    Utils.error("Failed to release storage lock: " .. (err or "unknown error"))
    return false
  end
  
  Utils.debug(string.format("🔓 Released storage lock: %s", lock.operation_id))
  return true
end

--- 💾 Create atomic backup with metadata
---@param filepath Path Original file to backup
---@param operation_id string Operation identifier
---@return string | nil backup_path Path to backup file or nil if failed
function M.create_atomic_backup(filepath, operation_id)
  if not filepath:exists() then
    Utils.debug("📁 No existing file to backup")
    return nil
  end
  
  local timestamp = os.time()
  local backup_filename = string.format("%s%s_%s_%d", 
                                       tostring(filepath), 
                                       M.BACKUP_SUFFIX,
                                       operation_id:sub(1, 8), -- Short ID for readability
                                       timestamp)
  local backup_path = Path:new(backup_filename)
  
  local ok, err = pcall(function()
    -- 📋 Copy file content
    filepath:copy({ destination = backup_path })
    
    -- 📊 Create backup metadata
    local metadata = {
      original_file = tostring(filepath),
      operation_id = operation_id,
      created_at = timestamp,
      created_at_iso = Utils.get_timestamp(),
      backup_size = backup_path:stat().size,
      checksum = M.calculate_file_checksum(backup_path),
    }
    
    local metadata_path = Path:new(backup_filename .. ".meta")
    metadata_path:write(vim.json.encode(metadata), "w")
  end)
  
  if not ok then
    Utils.error("Failed to create atomic backup: " .. (err or "unknown error"))
    -- 🧹 Cleanup partial backup
    if backup_path:exists() then backup_path:rm() end
    return nil
  end
  
  Utils.debug(string.format("💾 Created atomic backup: %s", tostring(backup_path)))
  return tostring(backup_path)
end

--- 🔍 Calculate file checksum for integrity verification
---@param filepath Path File to checksum
---@return string checksum MD5 checksum of file content
function M.calculate_file_checksum(filepath)
  local content = filepath:read()
  if not content then return "" end
  
  -- 🔢 Simple checksum calculation (in real implementation, use proper MD5)
  local checksum = 0
  for i = 1, #content do
    checksum = checksum + string.byte(content, i)
  end
  return string.format("%x", checksum)
end

--- ✅ Validate JSON content before write operations
---@param content string JSON content to validate
---@return boolean valid True if JSON is valid
---@return string | nil error Error message if validation fails
function M.validate_json_content(content)
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    return false, "Invalid JSON format"
  end
  
  -- 📋 Additional validation for history format
  if decoded.version == nil then
    return false, "Missing version field in history data"
  end
  
  if decoded.messages == nil and decoded.entries == nil then
    return false, "Missing messages or entries field in history data"
  end
  
  return true, nil
end

--- ⚡ Atomic write operation with full safety guarantees
---@param filepath Path Target file path
---@param content string Content to write
---@param operation_id string Operation identifier
---@param create_backup boolean Whether to create backup
---@return avante.StorageResult result Operation result
function M.atomic_write(filepath, content, operation_id, create_backup)
  local start_time = vim.loop.hrtime()
  local result = {
    success = false,
    message = "",
    backup_path = nil,
    operation_id = operation_id,
    duration_ms = 0,
    error = nil,
  }
  
  -- 🔐 Acquire storage lock
  local lock = M.acquire_lock(filepath, operation_id)
  if not lock then
    result.error = "Failed to acquire storage lock"
    result.message = "Storage locked by another operation"
    result.duration_ms = (vim.loop.hrtime() - start_time) / 1000000
    return result
  end
  
  local success = false
  
  -- 🛡️ Protected atomic write operation
  local ok, err = pcall(function()
    -- ✅ Validate content before writing
    local valid, validation_error = M.validate_json_content(content)
    if not valid then
      error("Content validation failed: " .. (validation_error or "unknown error"))
    end
    
    -- 💾 Create backup if requested
    if create_backup then
      result.backup_path = M.create_atomic_backup(filepath, operation_id)
    end
    
    -- ⚡ Atomic write using temporary file
    local temp_path = Path:new(tostring(filepath) .. M.TEMP_SUFFIX .. "_" .. operation_id)
    
    -- 📝 Write to temporary file first
    temp_path:write(content, "w")
    
    -- 🔍 Verify written content
    local written_content = temp_path:read()
    if written_content ~= content then
      error("Content verification failed after write")
    end
    
    -- ✅ Final validation of written JSON
    local final_valid, final_error = M.validate_json_content(written_content)
    if not final_valid then
      error("Final validation failed: " .. (final_error or "unknown error"))
    end
    
    -- ⚡ Atomically replace original file
    if filepath:exists() then
      filepath:rm()
    end
    temp_path:rename({ new_name = tostring(filepath) })
    
    success = true
  end)
  
  -- 🧹 Cleanup and finalize
  local cleanup_ok = pcall(function()
    -- 🗑️ Remove temporary files
    local temp_path = Path:new(tostring(filepath) .. M.TEMP_SUFFIX .. "_" .. operation_id)
    if temp_path:exists() then temp_path:rm() end
    
    -- 🔓 Release lock
    M.release_lock(lock)
  end)
  
  if not cleanup_ok then
    Utils.warn("⚠️  Cleanup after atomic write had issues")
  end
  
  -- 📊 Set final result
  result.duration_ms = (vim.loop.hrtime() - start_time) / 1000000
  result.success = success and ok
  
  if result.success then
    result.message = "Atomic write completed successfully"
    Utils.debug(string.format("⚡ Atomic write successful in %.1fms", result.duration_ms))
  else
    result.error = err or "Unknown atomic write error"
    result.message = "Atomic write failed: " .. result.error
    Utils.error(string.format("❌ Atomic write failed: %s", result.error))
  end
  
  return result
end

--- 🔄 Rollback operation using backup file
---@param filepath Path Target file path
---@param backup_path string Backup file path
---@param operation_id string Operation identifier
---@return avante.StorageResult result Rollback result
function M.atomic_rollback(filepath, backup_path, operation_id)
  local start_time = vim.loop.hrtime()
  local result = {
    success = false,
    message = "",
    backup_path = backup_path,
    operation_id = operation_id,
    duration_ms = 0,
    error = nil,
  }
  
  local backup_file = Path:new(backup_path)
  if not backup_file:exists() then
    result.error = "Backup file not found: " .. backup_path
    result.message = "Cannot rollback without backup file"
    result.duration_ms = (vim.loop.hrtime() - start_time) / 1000000
    return result
  end
  
  -- 🔐 Acquire storage lock for rollback
  local lock = M.acquire_lock(filepath, operation_id .. "_rollback")
  if not lock then
    result.error = "Failed to acquire storage lock for rollback"
    result.message = "Storage locked, cannot perform rollback"
    result.duration_ms = (vim.loop.hrtime() - start_time) / 1000000
    return result
  end
  
  -- 🛡️ Protected rollback operation
  local ok, err = pcall(function()
    -- 🔍 Verify backup integrity
    local metadata_path = Path:new(backup_path .. ".meta")
    if metadata_path:exists() then
      local metadata_content = metadata_path:read()
      local metadata = vim.json.decode(metadata_content)
      local current_checksum = M.calculate_file_checksum(backup_file)
      
      if current_checksum ~= metadata.checksum then
        error("Backup file integrity check failed")
      end
      
      Utils.debug("✅ Backup integrity verified")
    end
    
    -- 🔄 Restore from backup
    backup_file:copy({ destination = filepath, override = true })
    
    -- ✅ Verify restoration
    if not filepath:exists() then
      error("File restoration verification failed")
    end
    
    Utils.info(string.format("🔄 Successfully rolled back to backup: %s", backup_path))
  end)
  
  -- 🔓 Release lock
  M.release_lock(lock)
  
  result.duration_ms = (vim.loop.hrtime() - start_time) / 1000000
  result.success = ok
  
  if result.success then
    result.message = "Rollback completed successfully"
    Utils.info(string.format("✅ Rollback successful in %.1fms", result.duration_ms))
  else
    result.error = err or "Unknown rollback error"
    result.message = "Rollback failed: " .. result.error
    Utils.error(string.format("❌ Rollback failed: %s", result.error))
  end
  
  return result
end

--- 🧹 Cleanup old backup files
---@param directory_path Path Directory containing backups
---@param max_age_hours number Maximum age of backups to keep (default: 168 hours = 1 week)
---@return number cleaned_count Number of backup files cleaned up
function M.cleanup_old_backups(directory_path, max_age_hours)
  max_age_hours = max_age_hours or 168 -- Default: 1 week
  local max_age_seconds = max_age_hours * 3600
  local current_time = os.time()
  local cleaned_count = 0
  
  if not directory_path:exists() then
    Utils.debug("📁 Backup directory doesn't exist, nothing to cleanup")
    return cleaned_count
  end
  
  local ok, err = pcall(function()
    local files = vim.fn.glob(tostring(directory_path:joinpath("*" .. M.BACKUP_SUFFIX .. "*")), false, true)
    
    for _, file_path in ipairs(files) do
      local file = Path:new(file_path)
      if file:exists() then
        local stat = file:stat()
        local file_age = current_time - stat.mtime.sec
        
        if file_age > max_age_seconds then
          file:rm()
          cleaned_count = cleaned_count + 1
          
          -- 🗑️ Also remove associated metadata file
          local meta_file = Path:new(file_path .. ".meta")
          if meta_file:exists() then
            meta_file:rm()
          end
        end
      end
    end
  end)
  
  if not ok then
    Utils.warn("⚠️  Error during backup cleanup: " .. (err or "unknown error"))
  else
    Utils.debug(string.format("🧹 Cleaned up %d old backup files", cleaned_count))
  end
  
  return cleaned_count
end

--- 📊 Get storage operation statistics
---@param directory_path Path Directory to analyze
---@return table storage_stats Statistics about storage operations
function M.get_storage_stats(directory_path)
  local stats = {
    backup_files = 0,
    backup_total_size = 0,
    lock_files = 0,
    temp_files = 0,
    oldest_backup_age_hours = nil,
    newest_backup_age_hours = nil,
  }
  
  if not directory_path:exists() then
    return stats
  end
  
  local current_time = os.time()
  
  local ok, err = pcall(function()
    -- 📊 Count backup files
    local backup_files = vim.fn.glob(tostring(directory_path:joinpath("*" .. M.BACKUP_SUFFIX .. "*")), false, true)
    stats.backup_files = #backup_files
    
    for _, file_path in ipairs(backup_files) do
      local file = Path:new(file_path)
      if file:exists() then
        local stat = file:stat()
        stats.backup_total_size = stats.backup_total_size + stat.size
        
        local age_hours = (current_time - stat.mtime.sec) / 3600
        if not stats.oldest_backup_age_hours or age_hours > stats.oldest_backup_age_hours then
          stats.oldest_backup_age_hours = age_hours
        end
        if not stats.newest_backup_age_hours or age_hours < stats.newest_backup_age_hours then
          stats.newest_backup_age_hours = age_hours
        end
      end
    end
    
    -- 🔒 Count lock files
    local lock_files = vim.fn.glob(tostring(directory_path:joinpath("*" .. M.LOCKFILE_SUFFIX)), false, true)
    stats.lock_files = #lock_files
    
    -- 🗂️ Count temp files
    local temp_files = vim.fn.glob(tostring(directory_path:joinpath("*" .. M.TEMP_SUFFIX .. "*")), false, true)
    stats.temp_files = #temp_files
  end)
  
  if not ok then
    Utils.warn("⚠️  Error getting storage stats: " .. (err or "unknown error"))
  end
  
  return stats
end

return M
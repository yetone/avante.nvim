local Manager = require("avante.history.manager")
local Migration = require("avante.history.migration")
local Config = require("avante.config")
local Utils = require("avante.utils")
local Path = require("plenary.path")

---@class avante.history.startup
local M = {}

-- 📊 Startup state tracking
local startup_state = {
  initialized = false,
  migration_completed = false,
  last_check_time = 0,
}

---🚀 Initializes the history system on plugin startup
---@param force? boolean Force re-initialization
---@return boolean success
---@return string? error_message
function M.initialize(force)
  if startup_state.initialized and not force then
    return true, nil
  end
  
  Utils.debug("Initializing Avante history system...")
  
  -- 🏗️ Initialize storage manager
  local manager_success, manager_error = Manager.initialize()
  if not manager_success then
    Utils.error("Failed to initialize history manager:", manager_error)
    return false, manager_error
  end
  
  -- 🔄 Run auto-migration if enabled
  if Config.history.migration.auto_migrate then
    local migration_success, migration_error = M.run_startup_migration()
    if not migration_success then
      Utils.warn("Startup migration failed:", migration_error)
      -- 📌 Don't fail initialization if migration fails
    end
  end
  
  -- 🧹 Run cleanup if enabled
  if Config.history.retention.cleanup_on_startup then
    M.run_startup_cleanup()
  end
  
  startup_state.initialized = true
  startup_state.last_check_time = vim.uv.hrtime() / 1000000000
  
  Utils.debug("Avante history system initialized successfully")
  return true, nil
end

---🔄 Runs migration check and execution on startup
---@return boolean success
---@return string? error_message
function M.run_startup_migration()
  if startup_state.migration_completed then
    return true, nil
  end
  
  Utils.info("Running startup migration check...")
  
  local projects_dir = Path:new(Config.history.storage_path):joinpath("projects")
  if not projects_dir:exists() then
    Utils.debug("No projects directory found, skipping migration")
    startup_state.migration_completed = true
    return true, nil
  end
  
  local total_migrated = 0
  local total_failed = 0
  local project_count = 0
  
  -- 🔍 Scan all project directories
  for project_dir in projects_dir:iterdir() do
    if project_dir:is_dir() then
      local history_dir = project_dir:joinpath("history")
      if history_dir:exists() then
        project_count = project_count + 1
        
        -- 📋 Check if this project needs migration
        local legacy_files, scan_error = Migration.scan_for_legacy_files(tostring(history_dir))
        if scan_error then
          Utils.warn("Failed to scan project", project_dir:basename(), ":", scan_error)
          total_failed = total_failed + 1
          goto continue
        end
        
        if #legacy_files > 0 then
          Utils.info("Migrating", #legacy_files, "files in project", project_dir:basename())
          
          -- 🔄 Run migration for this project
          local result = Migration.migrate_directory(tostring(history_dir), Config.history.migration)
          
          total_migrated = total_migrated + result.migrated_count
          total_failed = total_failed + result.failed_count
          
          if not result.success then
            Utils.warn("Migration failed for project", project_dir:basename(), ":", 
                      table.concat(result.errors, ", "))
          else
            Utils.debug("Successfully migrated project", project_dir:basename())
          end
        end
      end
    end
    ::continue::
  end
  
  -- 📊 Report migration results
  if total_migrated > 0 or total_failed > 0 then
    local message = string.format("Startup migration completed: %d files migrated, %d failed across %d projects",
                                 total_migrated, total_failed, project_count)
    if total_failed == 0 then
      Utils.info(message)
    else
      Utils.warn(message)
    end
  else
    Utils.debug("No migration needed across", project_count, "projects")
  end
  
  startup_state.migration_completed = true
  return total_failed == 0, total_failed > 0 and "Some migrations failed" or nil
end

---🧹 Runs cleanup operations on startup
---@return boolean success
function M.run_startup_cleanup()
  if not Config.history.retention.enabled then
    return true
  end
  
  Utils.debug("Running startup cleanup...")
  
  local projects_dir = Path:new(Config.history.storage_path):joinpath("projects")
  if not projects_dir:exists() then
    return true
  end
  
  local total_cleaned = 0
  local total_archived = 0
  
  for project_dir in projects_dir:iterdir() do
    if project_dir:is_dir() then
      local history_dir = project_dir:joinpath("history")
      if history_dir:exists() then
        local cleaned, archived = M._cleanup_project_directory(tostring(history_dir))
        total_cleaned = total_cleaned + cleaned
        total_archived = total_archived + archived
      end
    end
  end
  
  if total_cleaned > 0 or total_archived > 0 then
    Utils.info("Startup cleanup completed:", total_cleaned, "files cleaned,", total_archived, "files archived")
  end
  
  return true
end

---🧹 Cleans up a single project directory
---@param history_dir_path string Path to history directory
---@return integer cleaned_count
---@return integer archived_count
function M._cleanup_project_directory(history_dir_path)
  local config = Config.history.retention
  local current_time = os.time()
  local max_age_seconds = config.max_age_days * 24 * 60 * 60
  local archive_threshold_seconds = config.archive_threshold_days * 24 * 60 * 60
  
  local cleaned_count = 0
  local archived_count = 0
  
  -- 📋 Get list of conversation files
  local engine = Manager.get_storage_engine()
  if not engine then
    return cleaned_count, archived_count
  end
  
  local conversations, list_error = engine:list(history_dir_path, { sort_by = "updated_at", sort_order = "desc" })
  if list_error then
    Utils.warn("Failed to list conversations for cleanup:", list_error)
    return cleaned_count, archived_count
  end
  
  -- 🔢 Check if we exceed max conversation limit
  if #conversations > config.max_conversations then
    local excess_count = #conversations - config.max_conversations
    Utils.debug("Project has", #conversations, "conversations, removing", excess_count, "oldest")
    
    -- 🗑️ Remove oldest conversations
    for i = #conversations - excess_count + 1, #conversations do
      local conversation = conversations[i]
      local filepath = Path:new(history_dir_path):joinpath(conversation.filename):absolute()
      
      local delete_success, delete_error = engine:delete(filepath)
      if delete_success then
        cleaned_count = cleaned_count + 1
        Utils.debug("Cleaned up old conversation:", conversation.filename)
      else
        Utils.warn("Failed to delete conversation", conversation.filename, ":", delete_error)
      end
    end
  end
  
  -- 📅 Archive old conversations
  local archive_dir = Path:new(history_dir_path):parent():joinpath("archive")
  
  for _, conversation in ipairs(conversations) do
    local age_seconds = current_time - conversation.updated_at
    
    if age_seconds > max_age_seconds and not conversation.archived then
      -- 🗑️ Delete very old conversations
      local filepath = Path:new(history_dir_path):joinpath(conversation.filename):absolute()
      local delete_success, delete_error = engine:delete(filepath)
      if delete_success then
        cleaned_count = cleaned_count + 1
        Utils.debug("Deleted old conversation:", conversation.filename)
      else
        Utils.warn("Failed to delete old conversation", conversation.filename, ":", delete_error)
      end
    elseif age_seconds > archive_threshold_seconds and not conversation.archived then
      -- 📦 Archive moderately old conversations
      if not archive_dir:exists() then
        archive_dir:mkdir({ parents = true })
      end
      
      local source_path = Path:new(history_dir_path):joinpath(conversation.filename):absolute()
      local archive_path = archive_dir:joinpath(conversation.filename):absolute()
      
      local archive_success, archive_error = engine:archive(source_path, archive_path)
      if archive_success then
        archived_count = archived_count + 1
        Utils.debug("Archived conversation:", conversation.filename)
        
        -- 🗑️ Remove from main directory after successful archive
        local delete_success, delete_error = engine:delete(source_path)
        if not delete_success then
          Utils.warn("Failed to remove archived conversation from main directory:", delete_error)
        end
      else
        Utils.warn("Failed to archive conversation", conversation.filename, ":", archive_error)
      end
    end
  end
  
  return cleaned_count, archived_count
end

---📊 Gets startup status information
---@return table status
function M.get_status()
  return {
    initialized = startup_state.initialized,
    migration_completed = startup_state.migration_completed,
    last_check_time = startup_state.last_check_time,
    config = {
      auto_migrate = Config.history.migration.auto_migrate,
      cleanup_on_startup = Config.history.retention.cleanup_on_startup,
      storage_engine = Config.history.storage.engine,
    },
  }
end

---🔄 Forces re-initialization (useful for development/testing)
---@return boolean success
---@return string? error_message
function M.force_reinitialize()
  startup_state.initialized = false
  startup_state.migration_completed = false
  return M.initialize(true)
end

---🎯 Checks if the system needs initialization
---@return boolean needs_init
function M.needs_initialization()
  return not startup_state.initialized
end

---⚡ Performs a quick health check of the history system
---@return boolean healthy
---@return string[] issues
function M.health_check()
  local issues = {}
  
  -- 🔍 Check storage directory
  local storage_path = Path:new(Config.history.storage_path)
  if not storage_path:exists() then
    table.insert(issues, "Storage directory does not exist: " .. tostring(storage_path))
  end
  
  -- 🔧 Check storage engine
  local engine = Manager.get_storage_engine()
  if not engine then
    table.insert(issues, "Storage engine not available")
  end
  
  -- 📋 Check configuration
  if not Config.history then
    table.insert(issues, "History configuration missing")
  end
  
  -- 🔄 Check migration state if auto-migration is enabled
  if Config.history.migration.auto_migrate and not startup_state.migration_completed then
    table.insert(issues, "Auto-migration enabled but not completed")
  end
  
  return #issues == 0, issues
end

return M
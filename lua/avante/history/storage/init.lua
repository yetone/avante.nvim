---⚡ Storage System Initialization for Avante
---Handles automatic startup, migration, and configuration of the new storage system

local Utils = require("avante.utils")
local M = {}

---🔄 Storage initialization state
M._initialized = false
M._initialization_error = nil

---⚙️ Initialize the storage system on plugin startup
---@param config table Avante configuration
---@return boolean success
---@return string? error_message
function M.initialize_on_startup(config)
  if M._initialized then
    return true -- Already initialized
  end
  
  Utils.debug("Initializing Avante history storage system...")
  
  -- 📊 Get history configuration
  local history_config = config.history or {}
  
  -- ⚙️ Initialize storage integration
  local StorageIntegration = require("avante.history.storage_integration")
  local success, error = StorageIntegration.initialize(history_config)
  
  if not success then
    M._initialization_error = error
    Utils.error("Failed to initialize history storage: " .. (error or "unknown error"))
    return false, error
  end
  
  -- ✅ Perform health check
  local healthy, health_report = StorageIntegration.storage_health_check()
  if not healthy then
    Utils.warn("Storage health check failed", health_report)
    -- 🔄 Continue anyway - system might still be usable
  else
    Utils.debug("Storage system initialized successfully")
  end
  
  -- 📊 Log storage statistics for debugging
  local stats = StorageIntegration.get_storage_stats()
  if stats and not stats.error then
    Utils.debug("Storage statistics:", stats)
  end
  
  M._initialized = true
  return true
end

---🔄 Auto-migration hook for plugin startup
---Called after successful initialization if auto-migration is enabled
---@param config table History configuration
function M.trigger_auto_migration(config)
  if not config.migration or not config.migration.auto_migrate then
    return
  end
  
  Utils.debug("Auto-migration is enabled, checking for projects to migrate...")
  
  -- 🔄 Use vim.defer_fn to avoid blocking plugin startup
  vim.defer_fn(function()
    local StorageIntegration = require("avante.history.storage_integration")
    local storage_manager = StorageIntegration._storage_manager
    
    if not storage_manager then
      Utils.warn("Storage manager not available for auto-migration")
      return
    end
    
    local migration_results = storage_manager:auto_migrate()
    
    -- 📊 Report migration results
    if migration_results.successful_projects and migration_results.successful_projects > 0 then
      Utils.info(string.format(
        "✅ Auto-migrated %d projects to new history format",
        migration_results.successful_projects
      ))
    end
    
    if migration_results.failed_projects and migration_results.failed_projects > 0 then
      Utils.warn(string.format(
        "⚠️  Failed to migrate %d projects - manual migration may be required",
        migration_results.failed_projects
      ))
      
      -- 📝 Log specific errors for debugging
      for project_name, result in pairs(migration_results.project_results or {}) do
        if not result.success then
          Utils.warn(string.format("Migration failed for project '%s': %s", project_name, result.error or "unknown error"))
        end
      end
    end
    
    if migration_results.no_projects_to_migrate then
      Utils.debug("No projects require migration")
    end
  end, 100) -- 100ms delay to avoid blocking startup
end

---🧹 Setup periodic cleanup if retention policies are enabled
---@param config table History configuration
function M.setup_periodic_cleanup(config)
  if not config.retention or not config.retention.enabled then
    return
  end
  
  local cleanup_interval = (config.retention.cleanup_interval_hours or 24) * 60 * 60 * 1000 -- Convert to milliseconds
  
  -- ⏰ Setup recurring cleanup timer
  local function run_cleanup()
    vim.defer_fn(function()
      local StorageIntegration = require("avante.history.storage_integration")
      local storage_manager = StorageIntegration._storage_manager
      
      if storage_manager then
        local success, cleanup_report = storage_manager:cleanup()
        if success then
          Utils.debug("Periodic cleanup completed:", cleanup_report)
        else
          Utils.warn("Periodic cleanup failed:", cleanup_report)
        end
      end
      
      -- 🔄 Schedule next cleanup
      run_cleanup()
    end, cleanup_interval)
  end
  
  -- 🕐 Start cleanup timer after initial delay
  vim.defer_fn(run_cleanup, cleanup_interval)
  
  Utils.debug(string.format("Periodic cleanup scheduled every %d hours", config.retention.cleanup_interval_hours or 24))
end

---📊 Create storage monitoring and metrics collection
---@param config table History configuration
function M.setup_monitoring(config)
  -- 📊 This would set up performance monitoring, metrics collection, etc.
  -- For now, just log that monitoring is available
  Utils.debug("Storage monitoring and metrics collection available")
  
  -- 🔧 Could add periodic stats logging, performance tracking, etc.
  if config.debug then
    vim.defer_fn(function()
      local StorageIntegration = require("avante.history.storage_integration")
      local stats = StorageIntegration.get_storage_stats()
      Utils.debug("Storage stats:", stats)
    end, 30000) -- Log stats every 30 seconds in debug mode
  end
end

---🏗️ Main setup function called from plugin initialization
---@param config table Full Avante configuration
---@return boolean success
---@return string? error_message
function M.setup(config)
  Utils.debug("Setting up Avante history storage system...")
  
  -- ⚙️ Initialize storage system
  local init_success, init_error = M.initialize_on_startup(config)
  if not init_success then
    return false, init_error
  end
  
  -- 🔄 Setup auto-migration
  M.trigger_auto_migration(config.history or {})
  
  -- 🧹 Setup periodic cleanup
  M.setup_periodic_cleanup(config.history or {})
  
  -- 📊 Setup monitoring
  M.setup_monitoring(config.history or {})
  
  Utils.debug("History storage system setup complete")
  return true
end

---✅ Check if storage system is initialized
---@return boolean initialized
---@return string? error_message
function M.is_initialized()
  return M._initialized, M._initialization_error
end

---🔄 Force re-initialization (useful for config changes)
---@param config table New configuration
---@return boolean success
---@return string? error_message
function M.reinitialize(config)
  M._initialized = false
  M._initialization_error = nil
  return M.setup(config)
end

---📊 Get initialization status and statistics
---@return table status
function M.get_status()
  local StorageIntegration = require("avante.history.storage_integration")
  local status = {
    initialized = M._initialized,
    initialization_error = M._initialization_error,
  }
  
  if M._initialized then
    local healthy, health_report = StorageIntegration.storage_health_check()
    status.healthy = healthy
    status.health_report = health_report
    
    local stats = StorageIntegration.get_storage_stats()
    status.stats = stats
  end
  
  return status
end

---🔧 Utility function to validate configuration
---@param config table Configuration to validate
---@return boolean valid
---@return string? error_message
function M.validate_config(config)
  if not config then
    return false, "Configuration is required"
  end
  
  local history_config = config.history
  if not history_config then
    return false, "History configuration is required"
  end
  
  -- ✅ Validate storage configuration
  if history_config.storage then
    local engine = history_config.storage.engine
    if engine and engine ~= "json" and engine ~= "sqlite" and engine ~= "hybrid" then
      return false, "Invalid storage engine: " .. engine
    end
  end
  
  -- ✅ Validate performance configuration
  if history_config.performance then
    if history_config.performance.compression then
      local algorithm = history_config.performance.compression.algorithm
      if algorithm and algorithm ~= "lz4" and algorithm ~= "gzip" then
        return false, "Invalid compression algorithm: " .. algorithm
      end
    end
  end
  
  return true
end

return M
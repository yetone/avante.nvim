---🏗️ Storage Manager for Avante history storage
---Coordinates between different storage engines and provides unified interface

local StorageInterface = require("avante.history.storage.interface")
local JSONStorageEngine = require("avante.history.storage.json_engine")
local Models = require("avante.history.storage.models")
local MigrationEngine = require("avante.history.storage.migration_engine")
local QueryEngine = require("avante.history.storage.query_engine")
local Utils = require("avante.utils")

local M = {}

---@class avante.storage.StorageManager
---@field config table Storage manager configuration
---@field storage_engine avante.storage.StorageInterface Active storage engine
---@field query_engine avante.storage.QueryEngine Query engine instance
---@field migration_engine avante.storage.MigrationEngine Migration engine instance
---@field _initialized boolean Whether the manager is initialized
local StorageManager = {}
StorageManager.__index = StorageManager

---🏗️ Create new storage manager instance
---@param config? table Storage configuration from avante config
---@return avante.storage.StorageManager
function M.new(config)
  config = config or {}
  
  -- 📁 Determine base path from config
  local base_path = config.storage and config.storage.base_path
  if not base_path then
    local storage_path = config.storage_path or Utils.join_paths(vim.fn.stdpath("state"), "avante")
    base_path = Utils.join_paths(storage_path, "projects")
  end
  
  -- ⚙️ Build storage engine configuration
  local engine_config = {
    base_path = base_path,
    compression = config.performance and config.performance.compression,
    cache = config.performance and config.performance.cache,
    backup = config.migration and { enabled = config.migration.backup_enabled },
  }
  
  -- 🏗️ Create storage engine based on configuration
  local engine_name = config.storage and config.storage.engine or "json"
  local storage_engine, engine_error = StorageInterface.create_engine(engine_name, engine_config)
  if not storage_engine then
    Utils.error("Failed to create storage engine: " .. (engine_error or "unknown error"))
    -- 🔄 Fallback to JSON engine
    storage_engine = JSONStorageEngine.new(engine_config)
  end
  
  -- 🔍 Create query engine
  local query_config = config.search or {}
  local query_engine = QueryEngine.new(storage_engine, query_config)
  
  -- 🔄 Create migration engine
  local migration_config = config.migration or {}
  local migration_engine = MigrationEngine.new(migration_config)
  
  local instance = {
    config = config,
    storage_engine = storage_engine,
    query_engine = query_engine,
    migration_engine = migration_engine,
    _initialized = false,
  }
  
  return setmetatable(instance, StorageManager)
end

---⚙️ Initialize the storage manager
---@param force? boolean Force re-initialization
---@return boolean success
---@return string? error_message
function StorageManager:initialize(force)
  if self._initialized and not force then
    return true
  end
  
  -- ⚙️ Initialize storage engine
  local init_success, init_error = self.storage_engine:initialize(force)
  if not init_success then
    return false, "Storage engine initialization failed: " .. (init_error or "unknown error")
  end
  
  -- 🔄 Register storage engines
  self:_register_engines()
  
  self._initialized = true
  return true
end

---🏷️ Register available storage engines
function StorageManager:_register_engines()
  -- 📄 Register JSON storage engine
  StorageInterface.register_engine("json", JSONStorageEngine)
  
  -- 🗄️ Register other engines if available
  -- SQLite and Hybrid engines would be registered here when implemented
end

---💾 Save chat history using unified format
---@param history avante.storage.UnifiedChatHistory | table Legacy history
---@param project_name string
---@return boolean success
---@return string? error_message
function StorageManager:save_history(history, project_name)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return false, init_error
    end
  end
  
  -- 🔄 Convert legacy format if needed
  local unified_history
  if history.version == Models.SCHEMA_VERSION then
    unified_history = history
  else
    -- 🔄 This is a legacy format, convert it
    unified_history = Models.convert_legacy_history(history, project_name)
  end
  
  -- 💾 Save using storage engine
  return self.storage_engine:save(unified_history, project_name)
end

---📖 Load chat history
---@param history_id string
---@param project_name string
---@return avante.storage.UnifiedChatHistory? history
---@return string? error_message
function StorageManager:load_history(history_id, project_name)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return nil, init_error
    end
  end
  
  return self.storage_engine:load(history_id, project_name)
end

---📋 List chat histories for a project
---@param project_name string
---@param opts? table Listing options
---@return table[] histories
---@return string? error_message
function StorageManager:list_histories(project_name, opts)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return {}, init_error
    end
  end
  
  return self.storage_engine:list(project_name, opts)
end

---🗑️ Delete chat history
---@param history_id string
---@param project_name string
---@return boolean success
---@return string? error_message
function StorageManager:delete_history(history_id, project_name)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return false, init_error
    end
  end
  
  return self.storage_engine:delete(history_id, project_name)
end

---🔍 Search chat histories
---@param query table Search query
---@param opts? table Search options
---@return table[] results
---@return string? error_message
function StorageManager:search_histories(query, opts)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return {}, init_error
    end
  end
  
  return self.query_engine:search(query, opts)
end

---🔄 Check if project needs migration
---@param project_name string
---@return boolean needs_migration
---@return string? current_version
---@return string? error_message
function StorageManager:needs_migration(project_name)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return false, nil, init_error
    end
  end
  
  return self.storage_engine:needs_migration(project_name)
end

---🔄 Migrate project to new format
---@param project_name string
---@param backup? boolean Create backup before migration
---@return boolean success
---@return table migration_summary
---@return string? error_message
function StorageManager:migrate_project(project_name, backup)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return false, {}, init_error
    end
  end
  
  return self.migration_engine:migrate_project(project_name, self.storage_engine)
end

---🔄 Auto-migrate projects on startup
---@return table migration_results
function StorageManager:auto_migrate()
  if not self.config.migration or not self.config.migration.auto_migrate then
    return { auto_migrate_disabled = true }
  end
  
  -- 🔍 Discover projects that need migration
  local base_path = Utils.join_paths(vim.fn.stdpath("state"), "avante", "projects")
  local projects = self.migration_engine:discover_projects_needing_migration(base_path)
  
  if #projects == 0 then
    return { no_projects_to_migrate = true }
  end
  
  Utils.info(string.format("Auto-migrating %d projects to new history format", #projects))
  
  -- 🔄 Batch migrate all projects
  local results = self.migration_engine:batch_migrate_projects(projects, self.storage_engine)
  
  -- 📊 Report results
  if results.successful_projects > 0 then
    Utils.info(string.format("Successfully migrated %d projects", results.successful_projects))
  end
  
  if results.failed_projects > 0 then
    Utils.warn(string.format("Failed to migrate %d projects", results.failed_projects))
  end
  
  return results
end

---📊 Get storage statistics
---@param project_name? string Optional project name for project-specific stats
---@return table stats
---@return string? error_message
function StorageManager:get_stats(project_name)
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      return {}, init_error
    end
  end
  
  return self.storage_engine:get_stats(project_name)
end

---✅ Perform health check on storage system
---@return boolean healthy
---@return table health_report
function StorageManager:health_check()
  local health_report = {
    initialized = self._initialized,
    engine_name = self.storage_engine.engine_name,
    checks = {},
  }
  
  if not self._initialized then
    local init_success, init_error = self:initialize()
    if not init_success then
      health_report.checks.initialization = { healthy = false, error = init_error }
      return false, health_report
    end
  end
  
  -- ✅ Storage engine health check
  local engine_healthy, engine_error = self.storage_engine:health_check()
  health_report.checks.storage_engine = {
    healthy = engine_healthy,
    error = engine_error,
  }
  
  -- 📊 Get basic stats
  local stats, stats_error = self.storage_engine:get_stats()
  health_report.checks.stats = {
    healthy = stats_error == nil,
    error = stats_error,
    stats = stats,
  }
  
  local overall_healthy = engine_healthy and stats_error == nil
  return overall_healthy, health_report
end

---🔄 Update storage configuration
---@param new_config table New configuration
---@return boolean success
---@return string? error_message
function StorageManager:update_config(new_config)
  -- 🔄 Update manager config
  self.config = vim.tbl_deep_extend("force", self.config, new_config)
  
  -- 🔄 Update storage engine config if needed
  local engine_config_updates = {}
  if new_config.performance then
    if new_config.performance.compression then
      engine_config_updates.compression = new_config.performance.compression
    end
    if new_config.performance.cache then
      engine_config_updates.cache = new_config.performance.cache
    end
  end
  
  if vim.tbl_count(engine_config_updates) > 0 then
    return self.storage_engine:update_config(engine_config_updates)
  end
  
  return true
end

---🧹 Cleanup old data based on retention policies
---@param project_name? string Optional project name to limit cleanup
---@return boolean success
---@return table cleanup_report
function StorageManager:cleanup(project_name)
  if not self.config.retention or not self.config.retention.enabled then
    return true, { retention_disabled = true }
  end
  
  -- 🧹 This would implement retention logic based on config
  -- For now, return success with no-op
  return true, { retention_not_implemented = true }
end

---🔧 Utility methods for backward compatibility

---📖 Convert legacy HistoryMessage to UnifiedHistoryMessage
---@param legacy_message avante.HistoryMessage
---@return avante.storage.UnifiedHistoryMessage
function StorageManager:convert_legacy_message(legacy_message)
  return Models.create_unified_message(
    legacy_message.message.role,
    legacy_message.message.content,
    {
      uuid = legacy_message.uuid,
      timestamp = legacy_message.timestamp,
      turn_id = legacy_message.turn_id,
      state = legacy_message.state,
      visible = legacy_message.visible,
      is_user_submission = legacy_message.is_user_submission,
      is_dummy = legacy_message.is_dummy,
      is_context = legacy_message.is_context,
      selected_code = legacy_message.selected_code,
      selected_filepaths = legacy_message.selected_filepaths,
      original_content = legacy_message.original_content,
      displayed_content = legacy_message.displayed_content,
      provider = legacy_message.provider,
      model = legacy_message.model,
    }
  )
end

---📖 Convert UnifiedHistoryMessage to legacy HistoryMessage format
---@param unified_message avante.storage.UnifiedHistoryMessage
---@return avante.HistoryMessage
function StorageManager:convert_to_legacy_message(unified_message)
  local Message = require("avante.history.message")
  local message = Message:new(
    unified_message.role,
    unified_message.content,
    {
      uuid = unified_message.uuid,
      timestamp = unified_message.timestamp,
      turn_id = unified_message.turn_id,
      state = unified_message.state,
      visible = unified_message.metadata.visible,
      is_user_submission = unified_message.metadata.is_user_submission,
      is_dummy = unified_message.metadata.is_dummy,
      is_context = unified_message.metadata.is_context,
      selected_code = unified_message.metadata.selected_code,
      selected_filepaths = unified_message.metadata.selected_filepaths,
      original_content = unified_message.metadata.original_content,
      displayed_content = unified_message.metadata.displayed_content,
      provider = unified_message.provider_info.provider,
      model = unified_message.provider_info.model,
    }
  )
  return message
end

-- 🌟 Global storage manager instance
M._global_instance = nil

---🌟 Get global storage manager instance
---@param config? table Storage configuration
---@return avante.storage.StorageManager
function M.get_instance(config)
  if not M._global_instance then
    M._global_instance = M.new(config)
  elseif config then
    -- 🔄 Update configuration if provided
    M._global_instance:update_config(config)
  end
  return M._global_instance
end

---🔄 Reset global instance (mainly for testing)
function M.reset_instance()
  M._global_instance = nil
end

return M
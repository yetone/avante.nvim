---🏗️ Storage interface abstraction for Avante history storage
---Provides a pluggable storage backend system supporting multiple storage engines

local M = {}

---@class avante.storage.StorageInterface
---@field engine_name string 🏷️ Name of the storage engine
---@field config table ⚙️ Engine-specific configuration
local StorageInterface = {}
StorageInterface.__index = StorageInterface

---🏗️ Create a new storage interface instance
---@param engine_name string
---@param config? table
---@return avante.storage.StorageInterface
function M.new(engine_name, config)
  local instance = {
    engine_name = engine_name,
    config = config or {},
  }
  return setmetatable(instance, StorageInterface)
end

---💾 Save a chat history to storage
---@param history avante.storage.UnifiedChatHistory
---@param project_name string
---@return boolean success
---@return string? error_message
function StorageInterface:save(history, project_name)
  error("save() method must be implemented by storage engine")
end

---📖 Load a chat history from storage
---@param history_id string
---@param project_name string
---@return avante.storage.UnifiedChatHistory? history
---@return string? error_message
function StorageInterface:load(history_id, project_name)
  error("load() method must be implemented by storage engine")
end

---📋 List all chat histories for a project
---@param project_name string
---@param opts? table Options for listing (limit, offset, sort, etc.)
---@return table[] histories List of history metadata
---@return string? error_message
function StorageInterface:list(project_name, opts)
  error("list() method must be implemented by storage engine")
end

---🗑️ Delete a chat history
---@param history_id string
---@param project_name string
---@return boolean success
---@return string? error_message
function StorageInterface:delete(history_id, project_name)
  error("delete() method must be implemented by storage engine")
end

---🔍 Search chat histories
---@param query table Search query parameters
---@param project_name string
---@param opts? table Search options
---@return table[] results Search results
---@return string? error_message
function StorageInterface:search(query, project_name, opts)
  error("search() method must be implemented by storage engine")
end

---📦 Archive old chat histories
---@param criteria table Archiving criteria (age, size, etc.)
---@param project_name string
---@return boolean success
---@return string? error_message
function StorageInterface:archive(criteria, project_name)
  error("archive() method must be implemented by storage engine")
end

---🧹 Cleanup storage (remove archived data, temp files, etc.)
---@param opts? table Cleanup options
---@return boolean success
---@return string? error_message
function StorageInterface:cleanup(opts)
  error("cleanup() method must be implemented by storage engine")
end

---📊 Get storage statistics
---@param project_name? string Optional project name for project-specific stats
---@return table stats Storage statistics
---@return string? error_message
function StorageInterface:get_stats(project_name)
  error("get_stats() method must be implemented by storage engine")
end

---⚙️ Initialize storage backend (create directories, schemas, etc.)
---@param force? boolean Force initialization even if already initialized
---@return boolean success
---@return string? error_message
function StorageInterface:initialize(force)
  error("initialize() method must be implemented by storage engine")
end

---✅ Check if storage backend is healthy and accessible
---@return boolean healthy
---@return string? error_message
function StorageInterface:health_check()
  error("health_check() method must be implemented by storage engine")
end

---🔧 Update storage configuration
---@param new_config table New configuration parameters
---@return boolean success
---@return string? error_message
function StorageInterface:update_config(new_config)
  self.config = vim.tbl_deep_extend("force", self.config, new_config)
  return true
end

---📝 Get current storage configuration
---@return table config Current configuration
function StorageInterface:get_config()
  return vim.deepcopy(self.config)
end

---🔄 Migration support - check if migration is needed
---@param project_name string
---@return boolean needs_migration
---@return string? current_version
---@return string? error_message
function StorageInterface:needs_migration(project_name)
  error("needs_migration() method must be implemented by storage engine")
end

---🔄 Perform migration to newer format
---@param project_name string
---@param backup? boolean Create backup before migration
---@return boolean success
---@return string? error_message
function StorageInterface:migrate(project_name, backup)
  error("migrate() method must be implemented by storage engine")
end

---💾 Create backup of storage data
---@param project_name string
---@param backup_path? string Optional custom backup path
---@return boolean success
---@return string backup_path
---@return string? error_message
function StorageInterface:create_backup(project_name, backup_path)
  error("create_backup() method must be implemented by storage engine")
end

---🔄 Restore from backup
---@param project_name string
---@param backup_path string Path to backup to restore from
---@return boolean success
---@return string? error_message
function StorageInterface:restore_backup(project_name, backup_path)
  error("restore_backup() method must be implemented by storage engine")
end

---🔒 Lock storage for exclusive access (useful for migrations)
---@param project_name string
---@param timeout? number Lock timeout in seconds
---@return boolean success
---@return string? lock_id
---@return string? error_message
function StorageInterface:acquire_lock(project_name, timeout)
  error("acquire_lock() method must be implemented by storage engine")
end

---🔓 Release storage lock
---@param lock_id string
---@return boolean success
---@return string? error_message
function StorageInterface:release_lock(lock_id)
  error("release_lock() method must be implemented by storage engine")
end

---⚡ Asynchronous operation support
---@class avante.storage.AsyncOperation
---@field id string Operation ID
---@field type string Operation type
---@field status "pending" | "running" | "completed" | "failed" Operation status
---@field progress number Progress percentage (0-100)
---@field result any Operation result when completed
---@field error string? Error message if failed

---⚡ Start an asynchronous operation
---@param operation_type string Type of operation
---@param params table Operation parameters
---@return string operation_id
---@return string? error_message
function StorageInterface:start_async_operation(operation_type, params)
  error("start_async_operation() method must be implemented by storage engine")
end

---⚡ Get status of an asynchronous operation
---@param operation_id string
---@return avante.storage.AsyncOperation? operation
---@return string? error_message
function StorageInterface:get_async_operation_status(operation_id)
  error("get_async_operation_status() method must be implemented by storage engine")
end

---⚡ Cancel an asynchronous operation
---@param operation_id string
---@return boolean success
---@return string? error_message
function StorageInterface:cancel_async_operation(operation_id)
  error("cancel_async_operation() method must be implemented by storage engine")
end

---🏷️ Storage engine registry
M._engines = {}

---📝 Register a storage engine
---@param name string Engine name
---@param engine_class table Engine class/constructor
function M.register_engine(name, engine_class)
  M._engines[name] = engine_class
end

---🏗️ Create storage engine instance by name
---@param name string Engine name
---@param config? table Engine configuration
---@return avante.storage.StorageInterface? engine
---@return string? error_message
function M.create_engine(name, config)
  local engine_class = M._engines[name]
  if not engine_class then
    return nil, string.format("Storage engine '%s' not found", name)
  end
  
  local success, result = pcall(engine_class.new, config)
  if not success then
    return nil, string.format("Failed to create engine '%s': %s", name, result)
  end
  
  return result
end

---📋 List available storage engines
---@return string[] engine_names
function M.list_engines()
  local names = {}
  for name, _ in pairs(M._engines) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

return M
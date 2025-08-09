---📁 JSON Storage Engine for Avante history storage
---Implements file-based storage using JSON format with optional compression

local StorageInterface = require("avante.history.storage.interface")
local Models = require("avante.history.storage.models")
local Utils = require("avante.utils")
local Path = require("avante.path")

---@class avante.storage.JSONStorageEngine : avante.storage.StorageInterface
local JSONStorageEngine = {}
JSONStorageEngine.__index = JSONStorageEngine

setmetatable(JSONStorageEngine, {
  __index = StorageInterface
})

---🏗️ Create new JSON storage engine instance
---@param config? table Configuration options
---@return avante.storage.JSONStorageEngine
function JSONStorageEngine.new(config)
  config = config or {}
  
  local default_config = {
    base_path = config.base_path or Utils.join_paths(vim.fn.stdpath("state"), "avante", "projects"),
    compression = {
      enabled = config.compression and config.compression.enabled or false,
      algorithm = config.compression and config.compression.algorithm or "lz4",
      min_size_threshold = config.compression and config.compression.min_size_threshold or 1024, -- 🗜️ Compress files larger than 1KB
    },
    backup = {
      enabled = config.backup and config.backup.enabled ~= false,
      max_backups = config.backup and config.backup.max_backups or 5,
    },
    cache = {
      enabled = config.cache and config.cache.enabled ~= false,
      max_size = config.cache and config.cache.max_size or 100, -- 💾 Cache up to 100 histories
      ttl_seconds = config.cache and config.cache.ttl_seconds or 300, -- ⏰ 5 minutes TTL
    },
  }
  
  local instance = StorageInterface.new("json", default_config)
  setmetatable(instance, JSONStorageEngine)
  
  -- 💾 Initialize cache
  instance._cache = {}
  instance._cache_access_times = {}
  
  -- ⚡ Async operations tracking
  instance._async_operations = {}
  
  return instance
end

---📁 Get project directory path
---@param project_name string
---@return string path
function JSONStorageEngine:_get_project_path(project_name)
  return Utils.join_paths(self.config.base_path, project_name, "history")
end

---📄 Get history file path
---@param history_id string
---@param project_name string
---@return string path
function JSONStorageEngine:_get_history_file_path(history_id, project_name)
  local project_path = self:_get_project_path(project_name)
  local filename = history_id .. ".json"
  if self.config.compression.enabled then
    filename = filename .. ".lz4"
  end
  return Utils.join_paths(project_path, filename)
end

---📋 Get metadata file path
---@param project_name string
---@return string path
function JSONStorageEngine:_get_metadata_file_path(project_name)
  local project_path = self:_get_project_path(project_name)
  return Utils.join_paths(project_path, "metadata.json")
end

---🗜️ Compress data if compression is enabled
---@param data string
---@return string compressed_data
---@return string? error_message
function JSONStorageEngine:_compress_data(data)
  if not self.config.compression.enabled or #data < self.config.compression.min_size_threshold then
    return data
  end
  
  -- 🔧 Simple compression simulation (in real implementation, use actual compression)
  -- For now, we'll just return the original data since Lua doesn't have built-in compression
  -- In a real implementation, you'd use a library like lz4 or zlib
  return data
end

---🗜️ Decompress data if it's compressed
---@param data string
---@param is_compressed? boolean
---@return string decompressed_data
---@return string? error_message
function JSONStorageEngine:_decompress_data(data, is_compressed)
  if not is_compressed or not self.config.compression.enabled then
    return data
  end
  
  -- 🔧 Simple decompression simulation
  -- In real implementation, use actual decompression
  return data
end

---💾 Add to cache
---@param key string
---@param value any
function JSONStorageEngine:_cache_set(key, value)
  if not self.config.cache.enabled then
    return
  end
  
  -- 🧹 Cleanup old entries if cache is full
  if #vim.tbl_keys(self._cache) >= self.config.cache.max_size then
    local oldest_key = nil
    local oldest_time = math.huge
    
    for cache_key, access_time in pairs(self._cache_access_times) do
      if access_time < oldest_time then
        oldest_time = access_time
        oldest_key = cache_key
      end
    end
    
    if oldest_key then
      self._cache[oldest_key] = nil
      self._cache_access_times[oldest_key] = nil
    end
  end
  
  self._cache[key] = {
    value = value,
    timestamp = os.time(),
  }
  self._cache_access_times[key] = os.time()
end

---💾 Get from cache
---@param key string
---@return any? value
function JSONStorageEngine:_cache_get(key)
  if not self.config.cache.enabled then
    return nil
  end
  
  local cached = self._cache[key]
  if not cached then
    return nil
  end
  
  -- ⏰ Check TTL
  if os.time() - cached.timestamp > self.config.cache.ttl_seconds then
    self._cache[key] = nil
    self._cache_access_times[key] = nil
    return nil
  end
  
  self._cache_access_times[key] = os.time()
  return cached.value
end

---💾 Save a chat history to storage
---@param history avante.storage.UnifiedChatHistory
---@param project_name string
---@return boolean success
---@return string? error_message
function JSONStorageEngine:save(history, project_name)
  -- ✅ Validate history
  local is_valid, error_msg = Models.validate_unified_history(history)
  if not is_valid then
    return false, "Invalid history: " .. error_msg
  end
  
  -- 📁 Ensure project directory exists
  local project_path = self:_get_project_path(project_name)
  local success, err = Path.mkdir(project_path, true)
  if not success then
    return false, "Failed to create project directory: " .. (err or "unknown error")
  end
  
  -- 📊 Update history stats
  Models.update_history_stats(history)
  
  -- 💾 Serialize to JSON
  local json_data = vim.json.encode(history)
  if not json_data then
    return false, "Failed to serialize history to JSON"
  end
  
  -- 🗜️ Compress if needed
  local data_to_write, compress_error = self:_compress_data(json_data)
  if compress_error then
    return false, "Failed to compress data: " .. compress_error
  end
  
  -- 📄 Write to file
  local file_path = self:_get_history_file_path(history.uuid, project_name)
  local file, file_error = io.open(file_path, "w")
  if not file then
    return false, "Failed to open file for writing: " .. (file_error or "unknown error")
  end
  
  local write_success, write_error = pcall(file.write, file, data_to_write)
  file:close()
  
  if not write_success then
    return false, "Failed to write data to file: " .. (write_error or "unknown error")
  end
  
  -- 📋 Update metadata
  local metadata_success, metadata_error = self:_update_metadata(project_name, history)
  if not metadata_success then
    Utils.debug("Failed to update metadata:", metadata_error)
  end
  
  -- 💾 Cache the history
  self:_cache_set(history.uuid .. ":" .. project_name, history)
  
  return true
end

---📋 Update project metadata
---@param project_name string
---@param history avante.storage.UnifiedChatHistory
---@return boolean success
---@return string? error_message
function JSONStorageEngine:_update_metadata(project_name, history)
  local metadata_path = self:_get_metadata_file_path(project_name)
  local metadata = {}
  
  -- 📖 Load existing metadata
  local file = io.open(metadata_path, "r")
  if file then
    local content = file:read("*all")
    file:close()
    
    if content and content ~= "" then
      local success, parsed = pcall(vim.json.decode, content)
      if success then
        metadata = parsed
      end
    end
  end
  
  -- 📝 Initialize metadata structure
  metadata.histories = metadata.histories or {}
  metadata.latest = metadata.latest or {}
  metadata.stats = metadata.stats or {
    total_histories = 0,
    total_size_bytes = 0,
    last_updated = Utils.get_timestamp(),
  }
  
  -- 📊 Update history info
  metadata.histories[history.uuid] = {
    uuid = history.uuid,
    created_at = history.created_at,
    updated_at = history.updated_at,
    message_count = #history.messages,
    size_estimate = #vim.json.encode(history),
  }
  
  -- 📅 Update latest reference
  metadata.latest.uuid = history.uuid
  metadata.latest.updated_at = history.updated_at
  
  -- 📊 Update stats
  metadata.stats.total_histories = vim.tbl_count(metadata.histories)
  metadata.stats.last_updated = Utils.get_timestamp()
  
  -- 💾 Save metadata
  local metadata_json = vim.json.encode(metadata)
  local metadata_file, metadata_file_error = io.open(metadata_path, "w")
  if not metadata_file then
    return false, "Failed to open metadata file: " .. (metadata_file_error or "unknown error")
  end
  
  local write_success, write_error = pcall(metadata_file.write, metadata_file, metadata_json)
  metadata_file:close()
  
  if not write_success then
    return false, "Failed to write metadata: " .. (write_error or "unknown error")
  end
  
  return true
end

---📖 Load a chat history from storage
---@param history_id string
---@param project_name string
---@return avante.storage.UnifiedChatHistory? history
---@return string? error_message
function JSONStorageEngine:load(history_id, project_name)
  -- 💾 Check cache first
  local cached = self:_cache_get(history_id .. ":" .. project_name)
  if cached then
    return cached
  end
  
  local file_path = self:_get_history_file_path(history_id, project_name)
  
  -- 📄 Check if file exists
  local file = io.open(file_path, "r")
  if not file then
    return nil, "History file not found: " .. file_path
  end
  
  -- 📖 Read file content
  local content = file:read("*all")
  file:close()
  
  if not content or content == "" then
    return nil, "History file is empty"
  end
  
  -- 🗜️ Decompress if needed
  local is_compressed = string.match(file_path, "%.lz4$") ~= nil
  local json_data, decompress_error = self:_decompress_data(content, is_compressed)
  if decompress_error then
    return nil, "Failed to decompress data: " .. decompress_error
  end
  
  -- 🔄 Parse JSON
  local success, history = pcall(vim.json.decode, json_data)
  if not success then
    return nil, "Failed to parse JSON: " .. (history or "unknown error")
  end
  
  -- ✅ Validate loaded history
  local is_valid, error_msg = Models.validate_unified_history(history)
  if not is_valid then
    return nil, "Loaded history is invalid: " .. error_msg
  end
  
  -- 💾 Cache the loaded history
  self:_cache_set(history_id .. ":" .. project_name, history)
  
  return history
end

---📋 List all chat histories for a project
---@param project_name string
---@param opts? table Options for listing
---@return table[] histories
---@return string? error_message
function JSONStorageEngine:list(project_name, opts)
  opts = opts or {}
  
  local metadata_path = self:_get_metadata_file_path(project_name)
  local file = io.open(metadata_path, "r")
  if not file then
    return {}, nil -- 📁 No histories yet
  end
  
  local content = file:read("*all")
  file:close()
  
  if not content or content == "" then
    return {}, nil
  end
  
  local success, metadata = pcall(vim.json.decode, content)
  if not success then
    return {}, "Failed to parse metadata: " .. (metadata or "unknown error")
  end
  
  local histories = {}
  for uuid, info in pairs(metadata.histories or {}) do
    table.insert(histories, info)
  end
  
  -- 📊 Sort by update time (newest first)
  table.sort(histories, function(a, b)
    return a.updated_at > b.updated_at
  end)
  
  -- 📑 Apply pagination if specified
  if opts.limit then
    local offset = opts.offset or 0
    local limited = {}
    for i = offset + 1, math.min(offset + opts.limit, #histories) do
      table.insert(limited, histories[i])
    end
    return limited
  end
  
  return histories
end

---🗑️ Delete a chat history
---@param history_id string
---@param project_name string
---@return boolean success
---@return string? error_message
function JSONStorageEngine:delete(history_id, project_name)
  local file_path = self:_get_history_file_path(history_id, project_name)
  
  -- 🗑️ Remove file
  local success, error = os.remove(file_path)
  if not success then
    return false, "Failed to delete history file: " .. (error or "unknown error")
  end
  
  -- 📋 Update metadata
  local metadata_path = self:_get_metadata_file_path(project_name)
  local file = io.open(metadata_path, "r")
  if file then
    local content = file:read("*all")
    file:close()
    
    if content and content ~= "" then
      local parse_success, metadata = pcall(vim.json.decode, content)
      if parse_success and metadata.histories then
        metadata.histories[history_id] = nil
        metadata.stats.total_histories = vim.tbl_count(metadata.histories)
        metadata.stats.last_updated = Utils.get_timestamp()
        
        -- 💾 Save updated metadata
        local updated_json = vim.json.encode(metadata)
        local metadata_file = io.open(metadata_path, "w")
        if metadata_file then
          metadata_file:write(updated_json)
          metadata_file:close()
        end
      end
    end
  end
  
  -- 💾 Remove from cache
  self._cache[history_id .. ":" .. project_name] = nil
  self._cache_access_times[history_id .. ":" .. project_name] = nil
  
  return true
end

---⚙️ Initialize storage backend
---@param force? boolean
---@return boolean success
---@return string? error_message
function JSONStorageEngine:initialize(force)
  local success, err = Path.mkdir(self.config.base_path, true)
  if not success then
    return false, "Failed to create base directory: " .. (err or "unknown error")
  end
  
  return true
end

---✅ Health check
---@return boolean healthy
---@return string? error_message
function JSONStorageEngine:health_check()
  -- 📁 Check if base directory exists and is writable
  local base_path = self.config.base_path
  if vim.fn.isdirectory(base_path) == 0 then
    return false, "Base directory does not exist: " .. base_path
  end
  
  -- 📝 Test write access
  local test_file = Utils.join_paths(base_path, ".health_check_test")
  local file = io.open(test_file, "w")
  if not file then
    return false, "Cannot write to base directory: " .. base_path
  end
  
  file:write("health_check")
  file:close()
  
  -- 🧹 Clean up test file
  os.remove(test_file)
  
  return true
end

---🔄 Check if migration is needed
---@param project_name string
---@return boolean needs_migration
---@return string? current_version
---@return string? error_message
function JSONStorageEngine:needs_migration(project_name)
  local metadata_path = self:_get_metadata_file_path(project_name)
  local file = io.open(metadata_path, "r")
  if not file then
    -- 📁 No metadata file means either no history or legacy format
    local project_path = self:_get_project_path(project_name)
    if vim.fn.isdirectory(project_path) == 1 then
      -- 📁 Directory exists, might have legacy format
      return true, "legacy", nil
    else
      -- 📁 No history at all
      return false, nil, nil
    end
  end
  
  local content = file:read("*all")
  file:close()
  
  if not content or content == "" then
    return true, "legacy", nil
  end
  
  local success, metadata = pcall(vim.json.decode, content)
  if not success then
    return true, "legacy", "Failed to parse metadata"
  end
  
  local current_version = metadata.version or "legacy"
  return current_version ~= Models.SCHEMA_VERSION, current_version, nil
end

---📊 Get storage statistics
---@param project_name? string
---@return table stats
---@return string? error_message
function JSONStorageEngine:get_stats(project_name)
  local stats = {
    engine = "json",
    compression_enabled = self.config.compression.enabled,
    cache_enabled = self.config.cache.enabled,
    cache_size = vim.tbl_count(self._cache),
  }
  
  if project_name then
    local metadata_path = self:_get_metadata_file_path(project_name)
    local file = io.open(metadata_path, "r")
    if file then
      local content = file:read("*all")
      file:close()
      
      local success, metadata = pcall(vim.json.decode, content)
      if success and metadata.stats then
        stats.project = metadata.stats
      end
    end
  else
    -- 📊 Global stats across all projects
    stats.total_projects = 0
    stats.total_histories = 0
    
    -- 🔍 Scan all project directories
    for project_dir in vim.fs.dir(self.config.base_path) do
      local project_path = Utils.join_paths(self.config.base_path, project_dir)
      if vim.fn.isdirectory(project_path) == 1 then
        stats.total_projects = stats.total_projects + 1
        
        local metadata_path = Utils.join_paths(project_path, "history", "metadata.json")
        local file = io.open(metadata_path, "r")
        if file then
          local content = file:read("*all")
          file:close()
          
          local success, metadata = pcall(vim.json.decode, content)
          if success and metadata.stats then
            stats.total_histories = stats.total_histories + (metadata.stats.total_histories or 0)
          end
        end
      end
    end
  end
  
  return stats
end

-- 🔍 Implement remaining methods with basic functionality
function JSONStorageEngine:search(query, project_name, opts)
  return {}, "Search not implemented in basic JSON engine"
end

function JSONStorageEngine:archive(criteria, project_name)
  return true, nil -- 📁 No archiving in basic version
end

function JSONStorageEngine:cleanup(opts)
  return true, nil -- 🧹 No cleanup needed in basic version
end

function JSONStorageEngine:migrate(project_name, backup)
  return false, "Migration handled by migration engine"
end

function JSONStorageEngine:create_backup(project_name, backup_path)
  return false, "Backup not implemented in basic JSON engine"
end

function JSONStorageEngine:restore_backup(project_name, backup_path)
  return false, "Restore not implemented in basic JSON engine"
end

function JSONStorageEngine:acquire_lock(project_name, timeout)
  return false, nil, "Locking not implemented in basic JSON engine"
end

function JSONStorageEngine:release_lock(lock_id)
  return false, "Locking not implemented in basic JSON engine"
end

function JSONStorageEngine:start_async_operation(operation_type, params)
  return "", "Async operations not implemented in basic JSON engine"
end

function JSONStorageEngine:get_async_operation_status(operation_id)
  return nil, "Async operations not implemented in basic JSON engine"
end

function JSONStorageEngine:cancel_async_operation(operation_id)
  return false, "Async operations not implemented in basic JSON engine"
end

return JSONStorageEngine
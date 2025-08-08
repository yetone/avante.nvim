local Utils = require("avante.utils")
local Config = require("avante.config")
local Models = require("avante.history.models")
local Migration = require("avante.history.migration")
local JSONStorageEngine = require("avante.history.storage.json")
local Path = require("plenary.path")

---@class avante.history.manager
local M = {}

-- 🏗️ Storage engine instance
---@type avante.StorageInterface?
local storage_engine = nil

-- 🏃 Cache for frequently accessed histories
---@type table<string, {history: avante.UnifiedChatHistory, access_time: number}>
local history_cache = {}

-- 📊 Cache statistics
local cache_stats = {
  hits = 0,
  misses = 0,
  evictions = 0,
}

---🏗️ Initializes the history manager with configured storage engine
---@return boolean success
---@return string? error_message
function M.initialize()
  local config = Config.history
  
  -- 🔧 Select and initialize storage engine based on configuration
  local engine_name = config.storage.engine or "json"
  
  if engine_name == "json" then
    storage_engine = JSONStorageEngine:new(config.storage.json)
  elseif engine_name == "sqlite" then
    -- 🗄️ Try to load SQLite storage engine
    local ok, SQLiteStorageEngine = pcall(require, "avante.history.storage.sqlite")
    if not ok then
      Utils.warn("SQLite storage engine not available, falling back to JSON")
      storage_engine = JSONStorageEngine:new(config.storage.json)
    else
      storage_engine = SQLiteStorageEngine:new(config.storage.sqlite)
    end
  elseif engine_name == "hybrid" then
    -- 🔀 Try to load Hybrid storage engine
    local ok, HybridStorageEngine = pcall(require, "avante.history.storage.hybrid")
    if not ok then
      Utils.warn("Hybrid storage engine not available, falling back to JSON")
      storage_engine = JSONStorageEngine:new(config.storage.json)
    else
      storage_engine = HybridStorageEngine:new(config.storage.hybrid)
    end
  else
    Utils.error("Unknown storage engine:", engine_name)
    return false, "Unknown storage engine: " .. engine_name
  end
  
  -- 🚀 Initialize the storage engine
  local init_success, init_error = storage_engine:initialize(config)
  if not init_success then
    Utils.error("Failed to initialize storage engine:", init_error)
    return false, init_error
  end
  
  Utils.debug("History manager initialized with", storage_engine.name, "storage engine")
  return true, nil
end

---🔧 Gets the current storage engine
---@return avante.StorageInterface?
function M.get_storage_engine()
  if not storage_engine then
    local success, error_msg = M.initialize()
    if not success then
      Utils.error("Failed to initialize storage engine:", error_msg)
      return nil
    end
  end
  return storage_engine
end

---📁 Gets the history directory path for a buffer
---@param bufnr integer Buffer number
---@return string directory_path
function M.get_history_directory(bufnr)
  local project_root = Utils.root.get({ buf = bufnr })
  local path_with_separators = string.gsub(project_root, "/", "__")
  local dirname = string.gsub(path_with_separators, "[^A-Za-z0-9._]", "_")
  local project_dirname = "projects/" .. dirname
  
  return Path:new(Config.history.storage_path):joinpath(project_dirname):joinpath("history"):absolute()
end

---🔑 Generates cache key for a conversation
---@param bufnr integer
---@param filename? string
---@return string cache_key
function M._get_cache_key(bufnr, filename)
  local base_path = M.get_history_directory(bufnr)
  return base_path .. "/" .. (filename or "latest")
end

---🧹 Cleans up expired cache entries
function M._cleanup_cache()
  local config = Config.history.performance.caching
  if not config.enabled then return end
  
  local current_time = vim.uv.hrtime() / 1000000000 -- Convert to seconds
  local ttl = config.ttl_seconds
  
  for key, entry in pairs(history_cache) do
    if current_time - entry.access_time > ttl then
      history_cache[key] = nil
      cache_stats.evictions = cache_stats.evictions + 1
    end
  end
  
  -- 📏 Enforce cache size limit
  local cache_size = 0
  local entries = {}
  for key, entry in pairs(history_cache) do
    cache_size = cache_size + 1
    table.insert(entries, {key = key, access_time = entry.access_time})
  end
  
  if cache_size > config.max_size then
    -- 📅 Sort by access time and remove oldest entries
    table.sort(entries, function(a, b) return a.access_time < b.access_time end)
    
    local to_remove = cache_size - config.max_size
    for i = 1, to_remove do
      history_cache[entries[i].key] = nil
      cache_stats.evictions = cache_stats.evictions + 1
    end
  end
end

---🏃 Gets history from cache or loads from storage
---@param bufnr integer
---@param filename? string
---@return avante.UnifiedChatHistory?
---@return string? error_message
function M._get_cached_history(bufnr, filename)
  local config = Config.history.performance.caching
  if not config.enabled then
    return M._load_from_storage(bufnr, filename)
  end
  
  local cache_key = M._get_cache_key(bufnr, filename)
  local cached_entry = history_cache[cache_key]
  
  if cached_entry then
    -- 🎯 Cache hit - update access time
    cached_entry.access_time = vim.uv.hrtime() / 1000000000
    cache_stats.hits = cache_stats.hits + 1
    Utils.debug("Cache hit for", cache_key)
    return cached_entry.history, nil
  end
  
  -- 📖 Cache miss - load from storage
  cache_stats.misses = cache_stats.misses + 1
  local history, error_msg = M._load_from_storage(bufnr, filename)
  
  if history and not error_msg then
    -- 💾 Store in cache
    history_cache[cache_key] = {
      history = history,
      access_time = vim.uv.hrtime() / 1000000000,
    }
    
    -- 🧹 Cleanup cache if needed
    M._cleanup_cache()
    Utils.debug("Cached history for", cache_key)
  end
  
  return history, error_msg
end

---📖 Loads history from storage engine
---@param bufnr integer
---@param filename? string
---@return avante.UnifiedChatHistory?
---@return string? error_message
function M._load_from_storage(bufnr, filename)
  local engine = M.get_storage_engine()
  if not engine then
    return nil, "Storage engine not available"
  end
  
  local history_dir = M.get_history_directory(bufnr)
  local filepath
  
  if filename then
    filepath = Path:new(history_dir):joinpath(filename):absolute()
  else
    -- 📋 Get latest filename from metadata
    local metadata_path = Path:new(history_dir):joinpath("metadata.json")
    if metadata_path:exists() then
      local metadata_ok, metadata_content = pcall(function()
        return vim.json.decode(metadata_path:read())
      end)
      if metadata_ok and metadata_content.latest_filename then
        filepath = Path:new(history_dir):joinpath(metadata_content.latest_filename):absolute()
      end
    end
    
    -- 🔍 Fallback: find latest file by modification time
    if not filepath then
      local pattern = Path:new(history_dir):joinpath("*.json"):absolute()
      local files = vim.fn.glob(pattern, true, true)
      if #files > 0 then
        -- 📅 Sort by modification time
        table.sort(files, function(a, b)
          local stat_a = Path:new(a):stat()
          local stat_b = Path:new(b):stat()
          return (stat_a and stat_a.mtime.sec or 0) > (stat_b and stat_b.mtime.sec or 0)
        end)
        filepath = files[1]
      end
    end
  end
  
  if not filepath then
    return nil, "No history files found"
  end
  
  return engine:load(filepath)
end

---💾 Saves history to storage engine
---@param bufnr integer
---@param history avante.UnifiedChatHistory
---@return boolean success
---@return string? error_message
function M._save_to_storage(bufnr, history)
  local engine = M.get_storage_engine()
  if not engine then
    return false, "Storage engine not available"
  end
  
  local history_dir = M.get_history_directory(bufnr)
  local filepath = Path:new(history_dir):joinpath(history.filename or "0.json"):absolute()
  
  -- 📊 Update statistics before saving
  Models.update_statistics(history)
  
  local success, error_msg = engine:save(history, filepath)
  
  if success then
    -- 📋 Update metadata.json with latest filename
    local metadata_path = Path:new(history_dir):joinpath("metadata.json")
    local metadata = {}
    if metadata_path:exists() then
      local read_ok, content = pcall(function()
        return vim.json.decode(metadata_path:read())
      end)
      if read_ok then metadata = content end
    end
    
    metadata.latest_filename = history.filename
    local write_ok, write_err = pcall(function()
      metadata_path:write(vim.json.encode(metadata), "w")
    end)
    
    if not write_ok then
      Utils.warn("Failed to update metadata:", write_err)
    end
    
    -- 🔄 Update cache
    local config = Config.history.performance.caching
    if config.enabled then
      local cache_key = M._get_cache_key(bufnr, history.filename)
      history_cache[cache_key] = {
        history = history,
        access_time = vim.uv.hrtime() / 1000000000,
      }
    end
  end
  
  return success, error_msg
end

---📖 Loads conversation history for buffer (main entry point)
---@param bufnr integer Buffer number
---@param filename? string Optional specific filename to load
---@return avante.UnifiedChatHistory
function M.load(bufnr, filename)
  -- 🔄 Check for auto-migration if enabled
  if Config.history.migration.auto_migrate then
    local history_dir = M.get_history_directory(bufnr)
    Migration.auto_migrate_if_needed(history_dir, Config.history.migration)
  end
  
  local history, error_msg = M._get_cached_history(bufnr, filename)
  
  if history then
    Utils.debug("Loaded history with", #history.messages, "messages for buffer", bufnr)
    return history
  end
  
  -- 🏗️ Create new history if none exists
  if error_msg and error_msg:match("No history files found") then
    Utils.debug("Creating new history for buffer", bufnr)
    local new_history = Models.create_history({
      title = "New Conversation",
      filename = "0.json",
      project_info = {
        root_path = Utils.root.get({ buf = bufnr }),
      },
    })
    return new_history
  end
  
  Utils.warn("Failed to load history:", error_msg)
  -- 🚨 Return empty history as fallback
  return Models.create_history({
    title = "Fallback Conversation",
    filename = "0.json",
  })
end

---💾 Saves conversation history for buffer (main entry point)
---@param bufnr integer Buffer number
---@param history avante.UnifiedChatHistory
---@return boolean success
function M.save(bufnr, history)
  local config = Config.history.performance.async_operations
  
  if config.enabled then
    -- ⚡ Async save with debouncing
    local debounce_key = "save_" .. bufnr .. "_" .. (history.filename or "latest")
    
    -- 🕐 Cancel previous debounced save
    if M._debounce_timers and M._debounce_timers[debounce_key] then
      M._debounce_timers[debounce_key]:stop()
    end
    
    M._debounce_timers = M._debounce_timers or {}
    M._debounce_timers[debounce_key] = vim.defer_fn(function()
      local success, error_msg = M._save_to_storage(bufnr, history)
      if not success then
        Utils.error("Async save failed:", error_msg)
      else
        Utils.debug("Async save completed for buffer", bufnr)
      end
      M._debounce_timers[debounce_key] = nil
    end, config.debounce_ms)
    
    return true -- 📌 Return immediately for async operation
  else
    -- 🔄 Synchronous save
    local success, error_msg = M._save_to_storage(bufnr, history)
    if not success then
      Utils.error("Save failed:", error_msg)
    end
    return success
  end
end

---📋 Lists available conversations for buffer
---@param bufnr integer Buffer number
---@param opts? table Options for filtering/sorting
---@return avante.HistoryListItem[] conversations
function M.list(bufnr, opts)
  local engine = M.get_storage_engine()
  if not engine then
    Utils.error("Storage engine not available")
    return {}
  end
  
  local history_dir = M.get_history_directory(bufnr)
  local conversations, error_msg = engine:list(history_dir, opts)
  
  if error_msg then
    Utils.warn("Failed to list conversations:", error_msg)
    return {}
  end
  
  return conversations
end

---🗑️ Deletes a conversation
---@param bufnr integer Buffer number
---@param filename string Filename to delete
---@return boolean success
function M.delete(bufnr, filename)
  local engine = M.get_storage_engine()
  if not engine then
    return false
  end
  
  local history_dir = M.get_history_directory(bufnr)
  local filepath = Path:new(history_dir):joinpath(filename):absolute()
  
  local success, error_msg = engine:delete(filepath)
  
  if success then
    -- 🧹 Remove from cache
    local cache_key = M._get_cache_key(bufnr, filename)
    history_cache[cache_key] = nil
    
    -- 📋 Update metadata if this was the latest file
    local metadata_path = Path:new(history_dir):joinpath("metadata.json")
    if metadata_path:exists() then
      local metadata_ok, metadata = pcall(function()
        return vim.json.decode(metadata_path:read())
      end)
      
      if metadata_ok and metadata.latest_filename == filename then
        -- 🔍 Find next most recent file
        local remaining_conversations = M.list(bufnr, { sort_by = "updated_at", sort_order = "desc" })
        if #remaining_conversations > 0 then
          metadata.latest_filename = remaining_conversations[1].filename
        else
          metadata.latest_filename = nil
        end
        
        pcall(function()
          metadata_path:write(vim.json.encode(metadata), "w")
        end)
      end
    end
    
    Utils.debug("Deleted conversation", filename, "for buffer", bufnr)
  else
    Utils.error("Failed to delete conversation:", error_msg)
  end
  
  return success
end

---🔍 Searches conversations
---@param bufnr integer Buffer number
---@param query table Search parameters
---@return avante.HistorySearchResult[] results
function M.search(bufnr, query)
  local engine = M.get_storage_engine()
  if not engine or not engine:supports("search") then
    Utils.warn("Search not supported by current storage engine")
    return {}
  end
  
  local history_dir = M.get_history_directory(bufnr)
  local results, error_msg = engine:search(history_dir, query)
  
  if error_msg then
    Utils.warn("Search failed:", error_msg)
    return {}
  end
  
  return results
end

---📊 Gets storage statistics
---@param bufnr integer Buffer number
---@return table statistics
function M.get_stats(bufnr)
  local engine = M.get_storage_engine()
  if not engine then
    return {}
  end
  
  local history_dir = M.get_history_directory(bufnr)
  local stats, error_msg = engine:get_stats(history_dir)
  
  if error_msg then
    Utils.warn("Failed to get stats:", error_msg)
    return {}
  end
  
  -- 🏃 Add cache statistics
  stats.cache = cache_stats
  
  return stats
end

---🔄 Legacy compatibility: converts unified messages to legacy format for existing code
---@param history avante.UnifiedChatHistory
---@return avante.HistoryMessage[]
function M.get_history_messages(history)
  if not history.messages then
    Utils.warn("History has no messages array")
    return {}
  end
  
  -- 🔄 Convert unified messages to legacy HistoryMessage format
  return Models.to_legacy_messages(history.messages)
end

---🏗️ Creates a new conversation
---@param bufnr integer Buffer number
---@return avante.UnifiedChatHistory
function M.new(bufnr)
  local new_history = Models.create_history({
    title = "New Conversation",
    filename = M._generate_new_filename(bufnr),
    project_info = {
      root_path = Utils.root.get({ buf = bufnr }),
    },
  })
  
  Utils.debug("Created new conversation for buffer", bufnr)
  return new_history
end

---📂 Generates a new filename for a conversation
---@param bufnr integer Buffer number
---@return string filename
function M._generate_new_filename(bufnr)
  local history_dir = M.get_history_directory(bufnr)
  local dir_path = Path:new(history_dir)
  
  if not dir_path:exists() then
    return "0.json"
  end
  
  local pattern = dir_path:joinpath("*.json"):absolute()
  local files = vim.fn.glob(pattern, true, true)
  local max_num = -1
  
  for _, file in ipairs(files) do
    local basename = Path:new(file):basename()
    if basename ~= "metadata.json" then
      local num = tonumber(basename:match("^(%d+)%.json$"))
      if num and num > max_num then
        max_num = num
      end
    end
  end
  
  return (max_num + 1) .. ".json"
end

-- 🕐 Debounce timers storage
M._debounce_timers = {}

return M
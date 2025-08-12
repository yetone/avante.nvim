local Utils = require("avante.utils")

---@class avante.HistoryCache
local M = {}

--- 🚀 Cache configuration and constants
M.MAX_CACHE_SIZE = 50 -- Maximum number of histories to cache
M.CACHE_TTL_MS = 300000 -- Cache TTL: 5 minutes
M.MEMORY_CLEANUP_THRESHOLD = 100 * 1024 * 1024 -- 100MB memory threshold

--- 📊 Cache statistics tracking
---@class avante.CacheStats
---@field hits number Cache hits
---@field misses number Cache misses
---@field evictions number Cache evictions
---@field memory_cleanups number Memory cleanup operations
---@field total_requests number Total cache requests

--- 📋 Cached history entry
---@class avante.CachedHistory
---@field history avante.ChatHistory | avante.UnifiedChatHistory Cached history data
---@field filepath string File path for cache key
---@field cached_at number Timestamp when cached
---@field last_accessed number Last access timestamp
---@field access_count number Number of times accessed
---@field file_size number Original file size in bytes
---@field checksum string File content checksum for validation

--- 🗂️ Global cache storage and statistics
local cache_storage = {} ---@type table<string, avante.CachedHistory>
local cache_stats = {
  hits = 0,
  misses = 0,
  evictions = 0,
  memory_cleanups = 0,
  total_requests = 0,
} ---@type avante.CacheStats

--- 🔑 Generate cache key from filepath
---@param filepath string File path
---@return string cache_key Normalized cache key
function M.generate_cache_key(filepath)
  -- 📝 Normalize path separators and remove absolute path prefixes for consistency
  local normalized = tostring(filepath):gsub("\\", "/"):gsub("^/+", "")
  return normalized
end

--- 🔍 Calculate simple checksum for cache validation
---@param content string File content
---@return string checksum Content checksum
function M.calculate_checksum(content)
  local checksum = 0
  for i = 1, #content do
    checksum = (checksum * 31 + string.byte(content, i)) % 2^32
  end
  return string.format("%08x", checksum)
end

--- 📊 Get current cache statistics
---@return avante.CacheStats stats Current cache statistics
function M.get_stats()
  local current_time = os.time() * 1000
  local active_entries = 0
  local expired_entries = 0
  local total_memory = 0
  
  for _, cached in pairs(cache_storage) do
    if current_time - cached.cached_at < M.CACHE_TTL_MS then
      active_entries = active_entries + 1
      -- 🧮 Rough memory estimation
      total_memory = total_memory + cached.file_size + 1000 -- Add overhead estimate
    else
      expired_entries = expired_entries + 1
    end
  end
  
  local extended_stats = vim.tbl_extend("force", cache_stats, {
    active_entries = active_entries,
    expired_entries = expired_entries,
    total_entries = active_entries + expired_entries,
    estimated_memory_bytes = total_memory,
    hit_rate = cache_stats.total_requests > 0 and (cache_stats.hits / cache_stats.total_requests) or 0,
  })
  
  return extended_stats
end

--- 🧹 Clean up expired cache entries
---@param force_cleanup boolean | nil Force cleanup regardless of TTL
---@return number cleaned_count Number of entries cleaned up
function M.cleanup_expired(force_cleanup)
  local current_time = os.time() * 1000
  local cleaned_count = 0
  
  for cache_key, cached in pairs(cache_storage) do
    local is_expired = current_time - cached.cached_at > M.CACHE_TTL_MS
    local should_clean = force_cleanup or is_expired
    
    if should_clean then
      cache_storage[cache_key] = nil
      cleaned_count = cleaned_count + 1
    end
  end
  
  if cleaned_count > 0 then
    Utils.debug(string.format("🧹 Cleaned up %d cache entries", cleaned_count))
  end
  
  return cleaned_count
end

--- ⚖️ Enforce cache size limits with LRU eviction
function M.enforce_cache_limits()
  local cache_size = vim.tbl_count(cache_storage)
  
  if cache_size <= M.MAX_CACHE_SIZE then
    return
  end
  
  -- 📊 Sort by last accessed time (LRU)
  local entries_by_access = {}
  for cache_key, cached in pairs(cache_storage) do
    table.insert(entries_by_access, { key = cache_key, cached = cached })
  end
  
  table.sort(entries_by_access, function(a, b)
    return a.cached.last_accessed < b.cached.last_accessed
  end)
  
  -- 🗑️ Remove oldest entries to get back under the limit
  local to_evict = cache_size - M.MAX_CACHE_SIZE
  for i = 1, to_evict do
    local entry = entries_by_access[i]
    cache_storage[entry.key] = nil
    cache_stats.evictions = cache_stats.evictions + 1
  end
  
  Utils.debug(string.format("⚖️  Evicted %d cache entries (LRU)", to_evict))
end

--- 💾 Store history in cache
---@param filepath string File path
---@param history avante.ChatHistory | avante.UnifiedChatHistory History data
---@param file_content string Original file content for checksum
---@return boolean success True if cached successfully
function M.set(filepath, history, file_content)
  local cache_key = M.generate_cache_key(filepath)
  local current_time = os.time() * 1000
  
  local cached_entry = {
    history = history,
    filepath = filepath,
    cached_at = current_time,
    last_accessed = current_time,
    access_count = 1,
    file_size = #file_content,
    checksum = M.calculate_checksum(file_content),
  }
  
  cache_storage[cache_key] = cached_entry
  
  -- 🧹 Maintain cache health
  M.enforce_cache_limits()
  M.cleanup_expired(false)
  
  Utils.debug(string.format("💾 Cached history: %s", cache_key))
  return true
end

--- 🔍 Retrieve history from cache with validation
---@param filepath string File path
---@param file_content string | nil Current file content for validation (optional)
---@return avante.ChatHistory | avante.UnifiedChatHistory | nil history Cached history or nil
---@return boolean hit True if cache hit occurred
function M.get(filepath, file_content)
  cache_stats.total_requests = cache_stats.total_requests + 1
  local cache_key = M.generate_cache_key(filepath)
  local cached = cache_storage[cache_key]
  
  if not cached then
    cache_stats.misses = cache_stats.misses + 1
    return nil, false
  end
  
  local current_time = os.time() * 1000
  
  -- ⏰ Check if cache entry is expired
  if current_time - cached.cached_at > M.CACHE_TTL_MS then
    cache_storage[cache_key] = nil
    cache_stats.misses = cache_stats.misses + 1
    Utils.debug(string.format("⏰ Cache expired: %s", cache_key))
    return nil, false
  end
  
  -- 🔍 Validate cache integrity if file content is provided
  if file_content then
    local current_checksum = M.calculate_checksum(file_content)
    if current_checksum ~= cached.checksum then
      cache_storage[cache_key] = nil
      cache_stats.misses = cache_stats.misses + 1
      Utils.debug(string.format("🔍 Cache invalidated (checksum mismatch): %s", cache_key))
      return nil, false
    end
  end
  
  -- 🎯 Cache hit - update access statistics
  cached.last_accessed = current_time
  cached.access_count = cached.access_count + 1
  cache_stats.hits = cache_stats.hits + 1
  
  Utils.debug(string.format("🎯 Cache hit: %s (accessed %d times)", cache_key, cached.access_count))
  return cached.history, true
end

--- 🗑️ Remove specific entry from cache
---@param filepath string File path to remove
---@return boolean removed True if entry was removed
function M.invalidate(filepath)
  local cache_key = M.generate_cache_key(filepath)
  local was_cached = cache_storage[cache_key] ~= nil
  
  if was_cached then
    cache_storage[cache_key] = nil
    Utils.debug(string.format("🗑️  Invalidated cache entry: %s", cache_key))
  end
  
  return was_cached
end

--- 🔄 Clear all cache entries
function M.clear_all()
  local entry_count = vim.tbl_count(cache_storage)
  cache_storage = {}
  
  -- 📊 Reset stats but keep counters for analysis
  cache_stats.memory_cleanups = cache_stats.memory_cleanups + 1
  
  Utils.info(string.format("🔄 Cleared all cache entries (%d removed)", entry_count))
end

--- 🧠 Smart cache preloading for frequently accessed files
---@param directory_path string Directory to preload
---@param max_preload number | nil Maximum files to preload (default: 10)
function M.preload_frequent_histories(directory_path, max_preload)
  max_preload = max_preload or 10
  
  local Path = require("plenary.path")
  local dir = Path:new(directory_path)
  
  if not dir:exists() then
    return
  end
  
  local files = vim.fn.glob(tostring(dir:joinpath("*.json")), false, true)
  local file_stats = {}
  
  -- 📊 Collect file statistics for smart preloading
  for _, filepath in ipairs(files) do
    if not filepath:match("metadata.json") then
      local file = Path:new(filepath)
      if file:exists() then
        local stat = file:stat()
        table.insert(file_stats, {
          path = filepath,
          size = stat.size,
          mtime = stat.mtime.sec,
          score = stat.mtime.sec - (stat.size / 1000), -- Recent + small = higher score
        })
      end
    end
  end
  
  -- 📊 Sort by preload score
  table.sort(file_stats, function(a, b) return a.score > b.score end)
  
  -- 🚀 Preload top files
  local preloaded_count = 0
  for i = 1, math.min(max_preload, #file_stats) do
    local file_info = file_stats[i]
    local cache_key = M.generate_cache_key(file_info.path)
    
    -- Skip if already cached
    if not cache_storage[cache_key] then
      local ok, content = pcall(function()
        return Path:new(file_info.path):read()
      end)
      
      if ok and content then
        local history_ok, history = pcall(vim.json.decode, content)
        if history_ok then
          M.set(file_info.path, history, content)
          preloaded_count = preloaded_count + 1
        end
      end
    end
  end
  
  if preloaded_count > 0 then
    Utils.info(string.format("🧠 Preloaded %d histories into cache", preloaded_count))
  end
end

--- 📊 Get formatted cache report for debugging
---@return string report Formatted cache status report
function M.get_status_report()
  local stats = M.get_stats()
  
  local report = string.format([[
🗂️  Avante History Cache Status
  📊 Statistics:
    - Total Requests: %d
    - Cache Hits: %d (%.1f%%)
    - Cache Misses: %d
    - Evictions: %d
    - Memory Cleanups: %d
  
  📋 Current State:
    - Active Entries: %d
    - Expired Entries: %d
    - Estimated Memory: %.1f KB
    - Max Cache Size: %d
    - Cache TTL: %.1f minutes
]], 
    stats.total_requests,
    stats.hits, stats.hit_rate * 100,
    stats.misses,
    stats.evictions,
    stats.memory_cleanups,
    stats.active_entries,
    stats.expired_entries,
    stats.estimated_memory_bytes / 1024,
    M.MAX_CACHE_SIZE,
    M.CACHE_TTL_MS / 60000
  )
  
  return report
end

-- 🔄 Initialize cache with periodic cleanup
vim.defer_fn(function()
  -- 🧹 Schedule periodic cleanup every 2 minutes
  local function schedule_cleanup()
    M.cleanup_expired(false)
    vim.defer_fn(schedule_cleanup, 120000) -- 2 minutes
  end
  schedule_cleanup()
end, 120000)

return M
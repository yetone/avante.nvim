local StorageInterface = require("avante.history.storage.interface").StorageInterface
local Models = require("avante.history.models")
local Utils = require("avante.utils")
local Path = require("plenary.path")

---@class avante.JSONStorageEngine : avante.StorageInterface
local JSONStorageEngine = StorageInterface:new("json", "1.0.0", {
  compression = true,  -- 📦 LZ4 compression support
  encryption = false,
  search = true,       -- 🔍 Basic text search
  indexing = false,
  transactions = false,
})

---🏗️ Creates a new JSON storage engine instance
---@param config? table Configuration options
---@return avante.JSONStorageEngine
function JSONStorageEngine:new(config)
  config = config or {}
  
  local obj = StorageInterface.new(self, "json", "1.0.0", {
    compression = config.compression ~= false,
    encryption = false,
    search = true,
    indexing = false,
    transactions = false,
  })
  
  obj.config = vim.tbl_extend("force", {
    compression_threshold = 1024, -- 📦 Compress files larger than 1KB
    compression_level = 1,        -- 🚀 Fast compression
    backup_on_save = true,        -- 🔄 Create backups before saving
    max_backups = 3,              -- 🗃️ Keep max 3 backups per file
  }, config)
  
  return setmetatable(obj, self)
end

---📦 Compresses content using LZ4 if available and above threshold
---@param content string Content to compress
---@return string compressed_content
---@return boolean was_compressed
function JSONStorageEngine:_compress(content)
  if #content < self.config.compression_threshold then
    return content, false
  end
  
  -- 📦 Try to use LZ4 compression if available
  local ok, lz4 = pcall(require, "lz4")
  if not ok then
    Utils.debug("LZ4 compression not available, storing uncompressed")
    return content, false
  end
  
  local compressed = lz4.compress(content, self.config.compression_level)
  if compressed and #compressed < #content then
    Utils.debug("Compressed", #content, "bytes to", #compressed, "bytes")
    return compressed, true
  end
  
  return content, false
end

---📦 Decompresses content if it was compressed
---@param content string Content to decompress
---@param was_compressed boolean Whether content was compressed
---@return string decompressed_content
function JSONStorageEngine:_decompress(content, was_compressed)
  if not was_compressed then
    return content
  end
  
  local ok, lz4 = pcall(require, "lz4")
  if not ok then
    error("LZ4 compression not available for decompression")
  end
  
  return lz4.decompress(content)
end

---🔄 Creates a backup of existing file
---@param filepath Path File to backup
---@return boolean success
function JSONStorageEngine:_create_backup(filepath)
  if not self.config.backup_on_save or not filepath:exists() then
    return true
  end
  
  local backup_dir = filepath:parent():joinpath(".backups")
  if not backup_dir:exists() then
    backup_dir:mkdir({ parents = true })
  end
  
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local backup_name = filepath:basename() .. "." .. timestamp .. ".backup"
  local backup_path = backup_dir:joinpath(backup_name)
  
  local ok, err = pcall(function()
    filepath:copy({ destination = backup_path })
  end)
  
  if ok then
    -- 🧹 Cleanup old backups
    self:_cleanup_old_backups(backup_dir, filepath:basename())
    Utils.debug("Created backup at", tostring(backup_path))
    return true
  else
    Utils.warn("Failed to create backup:", err)
    return false
  end
end

---🧹 Removes old backup files beyond the configured limit
---@param backup_dir Path Backup directory
---@param base_filename string Base filename to match
function JSONStorageEngine:_cleanup_old_backups(backup_dir, base_filename)
  local pattern = base_filename .. ".*.backup"
  local backups = {}
  
  for file in backup_dir:iterdir() do
    if file:is_file() and file:basename():match(pattern:gsub("%.", "%%."):gsub("%*", ".*")) then
      table.insert(backups, file)
    end
  end
  
  -- 📅 Sort by modification time (newest first)
  table.sort(backups, function(a, b)
    return a:stat().mtime.sec > b:stat().mtime.sec
  end)
  
  -- 🗑️ Remove excess backups
  for i = self.config.max_backups + 1, #backups do
    local ok, err = pcall(function()
      backups[i]:rm()
    end)
    if ok then
      Utils.debug("Removed old backup", tostring(backups[i]))
    else
      Utils.warn("Failed to remove old backup:", err)
    end
  end
end

---💾 Saves a conversation history to JSON file
---@param history avante.UnifiedChatHistory
---@param path string Storage path
---@return boolean success
---@return string? error_message
function JSONStorageEngine:save(history, path)
  local filepath = Path:new(path)
  
  -- 🔧 Validate and fix history structure
  local validated_history, warnings = Models.validate_and_fix(history)
  if #warnings > 0 then
    Utils.debug("History validation warnings:", table.concat(warnings, ", "))
  end
  
  -- 🔄 Create backup of existing file
  if not self:_create_backup(filepath) then
    Utils.warn("Failed to create backup, proceeding anyway")
  end
  
  -- 📊 Update statistics before saving
  Models.update_statistics(validated_history)
  
  -- 📝 Serialize to JSON
  local ok, json_content = pcall(vim.json.encode, validated_history)
  if not ok then
    return false, "Failed to serialize history to JSON: " .. json_content
  end
  
  -- 📦 Compress if enabled
  local final_content, was_compressed = self:_compress(json_content)
  
  -- 📁 Ensure parent directory exists
  local parent_dir = filepath:parent()
  if not parent_dir:exists() then
    parent_dir:mkdir({ parents = true })
  end
  
  -- 💾 Write to file
  local write_ok, write_err = pcall(function()
    filepath:write(final_content, "w")
  end)
  
  if not write_ok then
    return false, "Failed to write file: " .. (write_err or "unknown error")
  end
  
  -- 📋 Store compression metadata if needed
  if was_compressed then
    local meta_path = Path:new(path .. ".meta")
    local meta_ok, meta_err = pcall(function()
      meta_path:write(vim.json.encode({ compressed = true, engine = "lz4" }), "w")
    end)
    if not meta_ok then
      Utils.warn("Failed to write compression metadata:", meta_err)
    end
  end
  
  Utils.debug("Saved history to", path, was_compressed and "(compressed)" or "")
  return true, nil
end

---📖 Loads a conversation history from JSON file
---@param path string Storage path
---@return avante.UnifiedChatHistory? history
---@return string? error_message
function JSONStorageEngine:load(path)
  local filepath = Path:new(path)
  
  if not filepath:exists() then
    return nil, "File does not exist: " .. path
  end
  
  -- 📖 Read file content
  local read_ok, content = pcall(function()
    return filepath:read()
  end)
  
  if not read_ok then
    return nil, "Failed to read file: " .. (content or "unknown error")
  end
  
  if not content or content == "" then
    return nil, "File is empty"
  end
  
  -- 📋 Check for compression metadata
  local meta_path = Path:new(path .. ".meta")
  local was_compressed = false
  if meta_path:exists() then
    local meta_ok, meta_content = pcall(function()
      return vim.json.decode(meta_path:read())
    end)
    if meta_ok and meta_content.compressed then
      was_compressed = true
    end
  end
  
  -- 📦 Decompress if needed
  local json_content = self:_decompress(content, was_compressed)
  
  -- 🔍 Parse JSON
  local parse_ok, history_data = pcall(vim.json.decode, json_content)
  if not parse_ok then
    return nil, "Failed to parse JSON: " .. (history_data or "invalid JSON")
  end
  
  -- 🔄 Handle legacy format migration
  local history
  if Models.is_legacy_format(history_data) then
    Utils.debug("Migrating legacy format for", path)
    history = Models.migrate_from_legacy(history_data)
  else
    history = history_data
  end
  
  -- 🔧 Validate and fix structure
  local validated_history, warnings = Models.validate_and_fix(history)
  if #warnings > 0 then
    Utils.debug("History validation warnings for", path, ":", table.concat(warnings, ", "))
  end
  
  -- 📁 Set filename for reference
  validated_history.filename = filepath:basename()
  
  Utils.debug("Loaded history from", path, 
             was_compressed and "(decompressed)" or "",
             "- messages:", #validated_history.messages)
  
  return validated_history, nil
end

---📋 Lists available conversations in directory
---@param base_path string Base storage directory
---@param opts? table Options for filtering/sorting
---@return avante.HistoryListItem[] conversations
---@return string? error_message
function JSONStorageEngine:list(base_path, opts)
  opts = opts or {}
  local base_dir = Path:new(base_path)
  
  if not base_dir:exists() then
    return {}, nil
  end
  
  local conversations = {}
  
  for file in base_dir:iterdir() do
    if file:is_file() and file:suffix() == ".json" and file:basename() ~= "metadata.json" then
      local item = self:_create_list_item(file)
      if item then
        table.insert(conversations, item)
      end
    end
  end
  
  -- 📊 Sort conversations
  local sort_by = opts.sort_by or "updated_at"
  local sort_order = opts.sort_order or "desc"
  
  table.sort(conversations, function(a, b)
    local a_val = a[sort_by]
    local b_val = b[sort_by]
    
    if sort_order == "desc" then
      return a_val > b_val
    else
      return a_val < b_val
    end
  end)
  
  -- 🔍 Apply filters
  if opts.archived ~= nil then
    conversations = vim.tbl_filter(function(conv)
      return conv.archived == opts.archived
    end, conversations)
  end
  
  if opts.tags then
    conversations = vim.tbl_filter(function(conv)
      if not conv.tags then return false end
      for _, required_tag in ipairs(opts.tags) do
        if not vim.tbl_contains(conv.tags, required_tag) then
          return false
        end
      end
      return true
    end, conversations)
  end
  
  return conversations, nil
end

---📋 Creates a list item from a conversation file
---@param filepath Path
---@return avante.HistoryListItem?
function JSONStorageEngine:_create_list_item(filepath)
  local stat = filepath:stat()
  if not stat then
    return nil
  end
  
  -- 📖 Try to read basic info without full parsing
  local read_ok, content = pcall(function()
    return filepath:read()
  end)
  
  if not read_ok or not content then
    return nil
  end
  
  -- 🔍 Quick parse for metadata
  local parse_ok, data = pcall(vim.json.decode, content)
  if not parse_ok then
    return nil
  end
  
  local message_count = 0
  if data.messages then
    message_count = #data.messages
  elseif data.entries then
    -- 📊 Count legacy entries
    message_count = #data.entries * 2 -- Rough estimate (request + response)
  end
  
  return {
    uuid = data.uuid or Utils.uuid(),
    title = data.title or "Untitled",
    filename = filepath:basename(),
    created_at = data.created_at or data.timestamp or stat.ctime.sec,
    updated_at = data.updated_at or stat.mtime.sec,
    message_count = message_count,
    archived = data.archived or false,
    size = stat.size,
    tags = data.tags,
  }
end

---🗑️ Deletes a conversation file
---@param path string Storage path
---@return boolean success
---@return string? error_message
function JSONStorageEngine:delete(path)
  local filepath = Path:new(path)
  
  if not filepath:exists() then
    return false, "File does not exist: " .. path
  end
  
  -- 🗑️ Remove main file
  local delete_ok, delete_err = pcall(function()
    filepath:rm()
  end)
  
  if not delete_ok then
    return false, "Failed to delete file: " .. (delete_err or "unknown error")
  end
  
  -- 🗑️ Remove compression metadata if exists
  local meta_path = Path:new(path .. ".meta")
  if meta_path:exists() then
    pcall(function()
      meta_path:rm()
    end)
  end
  
  Utils.debug("Deleted conversation at", path)
  return true, nil
end

---📦 Archives a conversation
---@param path string Storage path  
---@param archive_path string Archive destination
---@return boolean success
---@return string? error_message
function JSONStorageEngine:archive(path, archive_path)
  local source_path = Path:new(path)
  local dest_path = Path:new(archive_path)
  
  if not source_path:exists() then
    return false, "Source file does not exist: " .. path
  end
  
  -- 📁 Ensure archive directory exists
  local archive_dir = dest_path:parent()
  if not archive_dir:exists() then
    archive_dir:mkdir({ parents = true })
  end
  
  -- 📦 Copy file to archive location
  local copy_ok, copy_err = pcall(function()
    source_path:copy({ destination = dest_path })
  end)
  
  if not copy_ok then
    return false, "Failed to copy to archive: " .. (copy_err or "unknown error")
  end
  
  -- 📦 Copy metadata if exists
  local meta_source = Path:new(path .. ".meta")
  if meta_source:exists() then
    local meta_dest = Path:new(archive_path .. ".meta")
    pcall(function()
      meta_source:copy({ destination = meta_dest })
    end)
  end
  
  -- 🏷️ Update archived flag in destination
  local archive_history, load_err = self:load(archive_path)
  if archive_history then
    archive_history.archived = true
    archive_history.metadata.archived_at = Utils.get_timestamp()
    self:save(archive_history, archive_path)
  end
  
  Utils.debug("Archived conversation from", path, "to", archive_path)
  return true, nil
end

---🔍 Searches conversations for content
---@param base_path string Base storage directory
---@param query table Search parameters
---@return avante.HistorySearchResult[] results
---@return string? error_message
function JSONStorageEngine:search(base_path, query)
  local conversations, list_err = self:list(base_path)
  if list_err then
    return {}, list_err
  end
  
  local results = {}
  local search_term = query.text or ""
  local case_sensitive = query.case_sensitive or false
  
  if not case_sensitive then
    search_term = search_term:lower()
  end
  
  for _, conv in ipairs(conversations) do
    local conv_path = Path:new(base_path):joinpath(conv.filename)
    local history, load_err = self:load(tostring(conv_path))
    
    if history and not load_err then
      local matches = {}
      local relevance_score = 0
      local match_type = nil
      
      -- 🔍 Search in title
      local title_to_search = case_sensitive and history.title or history.title:lower()
      if title_to_search:find(search_term, 1, true) then
        table.insert(matches, "Title: " .. history.title)
        relevance_score = relevance_score + 0.5
        match_type = "title"
      end
      
      -- 🔍 Search in message content
      for _, message in ipairs(history.messages) do
        local content = ""
        if type(message.content) == "string" then
          content = message.content
        elseif type(message.content) == "table" and message.content.text then
          content = message.content.text
        end
        
        local content_to_search = case_sensitive and content or content:lower()
        if content_to_search:find(search_term, 1, true) then
          -- 📝 Extract context around match
          local match_start = content_to_search:find(search_term, 1, true)
          local context_start = math.max(1, match_start - 50)
          local context_end = math.min(#content, match_start + #search_term + 50)
          local context = content:sub(context_start, context_end)
          
          table.insert(matches, context)
          relevance_score = relevance_score + 0.3
          if not match_type then match_type = "content" end
        end
      end
      
      -- 🔍 Search in metadata
      if query.search_metadata then
        local metadata_str = vim.json.encode(history.metadata)
        local metadata_to_search = case_sensitive and metadata_str or metadata_str:lower()
        if metadata_to_search:find(search_term, 1, true) then
          table.insert(matches, "Metadata match")
          relevance_score = relevance_score + 0.1
          if not match_type then match_type = "metadata" end
        end
      end
      
      -- ✅ Add to results if matches found
      if #matches > 0 then
        table.insert(results, {
          uuid = history.uuid,
          title = history.title,
          filename = conv.filename,
          relevance_score = math.min(1.0, relevance_score),
          matched_content = matches,
          match_type = match_type,
        })
      end
    end
  end
  
  -- 📊 Sort by relevance score
  table.sort(results, function(a, b)
    return a.relevance_score > b.relevance_score
  end)
  
  return results, nil
end

---📊 Gets storage statistics
---@param base_path string Base storage directory
---@return avante.StorageStats statistics
---@return string? error_message
function JSONStorageEngine:get_stats(base_path)
  local conversations, list_err = self:list(base_path)
  if list_err then
    return {}, list_err
  end
  
  local stats = {
    total_conversations = #conversations,
    total_size = 0,
    archived_conversations = 0,
    average_conversation_size = 0,
    oldest_conversation = math.huge,
    newest_conversation = 0,
  }
  
  for _, conv in ipairs(conversations) do
    stats.total_size = stats.total_size + conv.size
    if conv.archived then
      stats.archived_conversations = stats.archived_conversations + 1
    end
    
    if conv.created_at < stats.oldest_conversation then
      stats.oldest_conversation = conv.created_at
    end
    if conv.updated_at > stats.newest_conversation then
      stats.newest_conversation = conv.updated_at
    end
  end
  
  if #conversations > 0 then
    stats.average_conversation_size = stats.total_size / #conversations
  end
  
  if stats.oldest_conversation == math.huge then
    stats.oldest_conversation = 0
  end
  
  return stats, nil
end

return JSONStorageEngine
---@class avante.history.storage.interface
local M = {}

---@class avante.StorageInterface
---@field name string Name of the storage engine
---@field version string Version of the storage engine
---@field capabilities table<string, boolean> Supported features
local StorageInterface = {}
StorageInterface.__index = StorageInterface

---🏗️ Creates a new storage interface instance
---@param name string
---@param version string
---@param capabilities? table<string, boolean>
---@return avante.StorageInterface
function StorageInterface:new(name, version, capabilities)
  local obj = {
    name = name,
    version = version,
    capabilities = capabilities or {
      compression = false,
      encryption = false,
      search = false,
      indexing = false,
      transactions = false,
    },
  }
  return setmetatable(obj, self)
end

---💾 Saves a conversation history
---@param history avante.UnifiedChatHistory
---@param path string Storage path
---@return boolean success
---@return string? error_message
function StorageInterface:save(history, path)
  error("save method must be implemented by storage engine")
end

---📖 Loads a conversation history
---@param path string Storage path
---@return avante.UnifiedChatHistory? history
---@return string? error_message
function StorageInterface:load(path)
  error("load method must be implemented by storage engine")
end

---📋 Lists available conversations
---@param base_path string Base storage directory
---@param opts? table Options for filtering/sorting
---@return avante.HistoryListItem[] conversations
---@return string? error_message
function StorageInterface:list(base_path, opts)
  error("list method must be implemented by storage engine")
end

---🗑️ Deletes a conversation
---@param path string Storage path
---@return boolean success
---@return string? error_message
function StorageInterface:delete(path)
  error("delete method must be implemented by storage engine")
end

---🔍 Searches conversations
---@param base_path string Base storage directory
---@param query table Search parameters
---@return avante.HistorySearchResult[] results
---@return string? error_message
function StorageInterface:search(base_path, query)
  if not self.capabilities.search then
    return {}, "Search not supported by this storage engine"
  end
  error("search method must be implemented by storage engine")
end

---📦 Archives a conversation
---@param path string Storage path
---@param archive_path string Archive destination
---@return boolean success
---@return string? error_message
function StorageInterface:archive(path, archive_path)
  error("archive method must be implemented by storage engine")
end

---📊 Gets storage statistics
---@param base_path string Base storage directory
---@return avante.StorageStats statistics
---@return string? error_message
function StorageInterface:get_stats(base_path)
  error("get_stats method must be implemented by storage engine")
end

---🧹 Performs cleanup operations
---@param base_path string Base storage directory
---@param opts? table Cleanup options
---@return boolean success
---@return string? error_message
function StorageInterface:cleanup(base_path, opts)
  -- 📌 Default implementation - storage engines can override
  return true, nil
end

---🔧 Initializes the storage engine
---@param config table Storage configuration
---@return boolean success
---@return string? error_message
function StorageInterface:initialize(config)
  -- 📌 Default implementation - storage engines can override
  return true, nil
end

---🎯 Checks if a feature is supported
---@param feature string Feature name
---@return boolean supported
function StorageInterface:supports(feature)
  return self.capabilities[feature] == true
end

---@class avante.HistoryListItem
---@field uuid string Conversation UUID
---@field title string Conversation title
---@field filename string Filename on disk
---@field created_at number Creation timestamp
---@field updated_at number Last update timestamp
---@field message_count number Number of messages
---@field archived boolean Whether conversation is archived
---@field size number File size in bytes
---@field tags? string[] Optional tags

---@class avante.HistorySearchResult
---@field uuid string Conversation UUID
---@field title string Conversation title
---@field filename string Filename on disk
---@field relevance_score number Search relevance (0-1)
---@field matched_content string[] Matched text snippets
---@field match_type "title" | "content" | "metadata" Type of match

---@class avante.StorageStats
---@field total_conversations number Total number of conversations
---@field total_size number Total storage size in bytes
---@field archived_conversations number Number of archived conversations
---@field average_conversation_size number Average conversation size
---@field oldest_conversation number Timestamp of oldest conversation
---@field newest_conversation number Timestamp of newest conversation

M.StorageInterface = StorageInterface

return M
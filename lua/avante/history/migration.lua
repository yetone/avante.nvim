-- 🔄 Migration engine for Avante.nvim history storage system
-- Handles conversion from legacy ChatHistoryEntry[] to unified HistoryMessage[] format

local Utils = require("avante.utils")
local Message = require("avante.history.message")

local M = {}

-- 📄 Current migration format version
M.CURRENT_VERSION = "2.0.0"
M.LEGACY_VERSION = "1.0.0"

---@class UnifiedChatHistory : avante.ChatHistory
---@field version string Migration version identifier
---@field migration_metadata table<string, any> Metadata about migration process

---@class MigrationResult
---@field success boolean
---@field error string | nil
---@field backup_path string | nil
---@field messages_count integer
---@field entries_count integer

---@class MigrationEngine
---@field backup_dir string Directory to store backup files
local MigrationEngine = {}
MigrationEngine.__index = MigrationEngine

-- 🏗️ Create new migration engine instance
---@param backup_dir string
---@return MigrationEngine
function M.new(backup_dir)
  local obj = {
    backup_dir = backup_dir or Utils.join_paths(vim.fn.stdpath("data"), "avante", "backups")
  }
  
  -- 📁 Ensure backup directory exists
  local backup_path = require("plenary.path"):new(obj.backup_dir)
  if not backup_path:exists() then
    backup_path:mkdir({ parents = true })
  end
  
  return setmetatable(obj, MigrationEngine)
end

-- 🔍 Detect if history uses legacy format
---@param history avante.ChatHistory
---@return boolean
function MigrationEngine:is_legacy_format(history)
  return history.entries ~= nil and history.messages == nil
end

-- 🔍 Detect if history uses modern format
---@param history avante.ChatHistory
---@return boolean
function MigrationEngine:is_modern_format(history)
  return history.messages ~= nil and (history.entries == nil or #history.entries == 0)
end

-- 🔍 Detect format version
---@param history avante.ChatHistory
---@return string
function MigrationEngine:detect_version(history)
  if history.version then
    return history.version
  elseif self:is_legacy_format(history) then
    return M.LEGACY_VERSION
  elseif self:is_modern_format(history) then
    return M.CURRENT_VERSION
  else
    return "unknown"
  end
end

-- 📋 Validate migration integrity
---@param history avante.ChatHistory
---@return boolean, string | nil
function MigrationEngine:validate_history(history)
  if not history then
    return false, "History is nil"
  end
  
  if not history.title then
    return false, "Missing required field: title"
  end
  
  if not history.timestamp then
    return false, "Missing required field: timestamp"
  end
  
  -- 🔍 Check for mixed formats (should not happen after migration)
  if history.entries and history.messages and #history.entries > 0 and #history.messages > 0 then
    return false, "History contains both legacy entries and modern messages"
  end
  
  return true, nil
end

-- 💾 Create backup of history before migration
---@param history avante.ChatHistory
---@param original_filename string
---@return string | nil backup_path
function MigrationEngine:create_backup(history, original_filename)
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local backup_filename = string.format("%s_%s_backup.json", 
    original_filename:gsub("%.json$", ""), timestamp)
  
  local backup_path = require("plenary.path"):new(self.backup_dir):joinpath(backup_filename)
  
  local success, error = pcall(function()
    backup_path:write(vim.json.encode(history), "w")
  end)
  
  if success then
    Utils.debug(string.format("Created backup at %s", tostring(backup_path)))
    return tostring(backup_path)
  else
    Utils.warn(string.format("Failed to create backup: %s", tostring(error)))
    return nil
  end
end

-- ↩️ Rollback from backup
---@param backup_path string
---@param target_path string
---@return boolean success
function MigrationEngine:rollback_from_backup(backup_path, target_path)
  local backup_file = require("plenary.path"):new(backup_path)
  local target_file = require("plenary.path"):new(target_path)
  
  if not backup_file:exists() then
    Utils.warn(string.format("Backup file not found: %s", backup_path))
    return false
  end
  
  local success, error = pcall(function()
    local backup_content = backup_file:read()
    target_file:write(backup_content, "w")
  end)
  
  if success then
    Utils.info(string.format("Successfully rolled back from backup: %s", backup_path))
    return true
  else
    Utils.error(string.format("Failed to rollback from backup: %s", tostring(error)))
    return false
  end
end

-- 🔧 Convert legacy ChatHistoryEntry to HistoryMessage
---@param entry avante.ChatHistoryEntry
---@return avante.HistoryMessage[]
---@return string | nil error
function MigrationEngine:convert_entry_to_messages(entry)
  local messages = {}
  
  -- 📋 Validate entry structure
  if not entry then
    return {}, "Entry is nil"
  end
  
  if not entry.timestamp then
    return {}, "Entry missing required timestamp field"
  end
  
  -- 👤 Convert user request to message
  if entry.request and entry.request ~= "" then
    local user_opts = {
      timestamp = entry.timestamp,
      is_user_submission = true,
      visible = entry.visible ~= false,  -- Default to true if not specified
    }
    
    -- 📁 Preserve selected file information
    if entry.selected_filepaths then
      user_opts.selected_filepaths = entry.selected_filepaths
    end
    
    -- 📄 Preserve selected code information
    if entry.selected_code then
      user_opts.selected_code = entry.selected_code
    end
    
    -- 🔗 Handle legacy selected_file format (single file)
    if entry.selected_file and entry.selected_file.filepath then
      if not user_opts.selected_filepaths then
        user_opts.selected_filepaths = { entry.selected_file.filepath }
      end
    end
    
    local user_message = Message:new("user", entry.request, user_opts)
    table.insert(messages, user_message)
  end
  
  -- 🤖 Convert assistant response to message
  if entry.response and entry.response ~= "" then
    local assistant_opts = {
      timestamp = entry.timestamp,
      visible = entry.visible ~= false,  -- Default to true if not specified
    }
    
    -- 🏷️ Preserve provider and model information
    if entry.provider then
      assistant_opts.provider = entry.provider
    end
    
    if entry.model then
      assistant_opts.model = entry.model
    end
    
    -- 📝 Handle original_response field if present
    if entry.original_response and entry.original_response ~= entry.response then
      assistant_opts.original_content = entry.original_response
    end
    
    local assistant_message = Message:new("assistant", entry.response, assistant_opts)
    table.insert(messages, assistant_message)
  end
  
  -- ⚠️ Warn if entry has no content
  if #messages == 0 then
    Utils.debug(string.format("Entry with timestamp %s has no request or response content", entry.timestamp))
  end
  
  return messages, nil
end

-- 🔍 Validate converted messages
---@param messages avante.HistoryMessage[]
---@return boolean success
---@return string | nil error
function MigrationEngine:validate_converted_messages(messages)
  for i, message in ipairs(messages) do
    if not message.message then
      return false, string.format("Message %d missing required 'message' field", i)
    end
    
    if not message.message.role then
      return false, string.format("Message %d missing required 'role' field", i)
    end
    
    if message.message.role ~= "user" and message.message.role ~= "assistant" then
      return false, string.format("Message %d has invalid role: %s", i, message.message.role)
    end
    
    if not message.message.content then
      return false, string.format("Message %d missing required 'content' field", i)
    end
    
    if not message.timestamp then
      return false, string.format("Message %d missing required 'timestamp' field", i)
    end
    
    if not message.uuid then
      return false, string.format("Message %d missing required 'uuid' field", i)
    end
  end
  
  return true, nil
end

-- 📊 Enhanced conversion statistics
---@class ConversionStats
---@field total_entries integer
---@field successful_entries integer
---@field failed_entries integer
---@field total_messages integer
---@field user_messages integer
---@field assistant_messages integer
---@field entries_with_files integer
---@field entries_with_code integer
---@field errors string[]

-- 📈 Create conversion stats tracker
---@return ConversionStats
function M.create_conversion_stats()
  return {
    total_entries = 0,
    successful_entries = 0,
    failed_entries = 0,
    total_messages = 0,
    user_messages = 0,
    assistant_messages = 0,
    entries_with_files = 0,
    entries_with_code = 0,
    errors = {}
  }
end

-- 📊 Update conversion statistics
---@param stats ConversionStats
---@param entry avante.ChatHistoryEntry
---@param messages avante.HistoryMessage[]
---@param error string | nil
function M.update_conversion_stats(stats, entry, messages, error)
  stats.total_entries = stats.total_entries + 1
  
  if error then
    stats.failed_entries = stats.failed_entries + 1
    table.insert(stats.errors, error)
    return
  end
  
  stats.successful_entries = stats.successful_entries + 1
  stats.total_messages = stats.total_messages + #messages
  
  -- 👤 Count user messages
  for _, message in ipairs(messages) do
    if message.message.role == "user" then
      stats.user_messages = stats.user_messages + 1
    elseif message.message.role == "assistant" then
      stats.assistant_messages = stats.assistant_messages + 1
    end
  end
  
  -- 📁 Track file attachments
  if entry.selected_filepaths or entry.selected_file then
    stats.entries_with_files = stats.entries_with_files + 1
  end
  
  -- 📄 Track code selections
  if entry.selected_code then
    stats.entries_with_code = stats.entries_with_code + 1
  end
end

-- 🔄 Perform legacy to modern format conversion
---@param history avante.ChatHistory
---@return UnifiedChatHistory, MigrationResult
function MigrationEngine:convert_legacy_to_modern(history)
  local result = {
    success = false,
    error = nil,
    backup_path = nil,
    messages_count = 0,
    entries_count = 0
  }
  
  -- 📋 Validate input history
  local is_valid, validation_error = self:validate_history(history)
  if not is_valid then
    result.error = "Pre-migration validation failed: " .. (validation_error or "unknown error")
    return history, result
  end
  
  -- 🔍 Check if already in modern format
  if self:is_modern_format(history) then
    result.success = true
    result.messages_count = #(history.messages or {})
    Utils.debug("History already in modern format")
    return history, result
  end
  
  -- 🚫 Ensure it's legacy format
  if not self:is_legacy_format(history) then
    result.error = "History is not in recognizable legacy format"
    return history, result
  end
  
  -- 📊 Count original entries and create conversion stats
  result.entries_count = #(history.entries or {})
  local conversion_stats = M.create_conversion_stats()
  
  -- 🔄 Convert entries to messages with error handling
  local converted_messages = {}
  for i, entry in ipairs(history.entries or {}) do
    local entry_messages, conversion_error = self:convert_entry_to_messages(entry)
    
    M.update_conversion_stats(conversion_stats, entry, entry_messages, conversion_error)
    
    if conversion_error then
      Utils.warn(string.format("Failed to convert entry %d: %s", i, conversion_error))
      -- 🔄 Continue with other entries instead of failing completely
      goto continue
    end
    
    -- ✅ Validate converted messages
    local messages_valid, validation_error = self:validate_converted_messages(entry_messages)
    if not messages_valid then
      Utils.warn(string.format("Entry %d validation failed: %s", i, validation_error))
      M.update_conversion_stats(conversion_stats, entry, {}, validation_error)
      goto continue
    end
    
    -- ➕ Add valid messages to result
    for _, msg in ipairs(entry_messages) do
      table.insert(converted_messages, msg)
    end
    
    ::continue::
  end
  
  -- 📊 Log conversion statistics
  if conversion_stats.failed_entries > 0 then
    Utils.warn(string.format(
      "Migration completed with %d failures out of %d entries. %d messages generated.",
      conversion_stats.failed_entries,
      conversion_stats.total_entries,
      conversion_stats.total_messages
    ))
  else
    Utils.info(string.format(
      "Migration successful: %d entries converted to %d messages (%d user, %d assistant)",
      conversion_stats.successful_entries,
      conversion_stats.total_messages,
      conversion_stats.user_messages,
      conversion_stats.assistant_messages
    ))
  end
  
  -- 🏗️ Create unified history
  local unified_history = vim.deepcopy(history)
  unified_history.messages = converted_messages
  unified_history.entries = nil  -- Remove legacy field
  unified_history.version = M.CURRENT_VERSION
  unified_history.migration_metadata = {
    migrated_at = Utils.get_timestamp(),
    source_version = M.LEGACY_VERSION,
    target_version = M.CURRENT_VERSION,
    original_entries_count = result.entries_count,
    converted_messages_count = #converted_messages,
    failed_entries_count = conversion_stats.failed_entries,
    successful_entries_count = conversion_stats.successful_entries,
    entries_with_files = conversion_stats.entries_with_files,
    entries_with_code = conversion_stats.entries_with_code,
    conversion_errors = conversion_stats.errors
  }
  
  result.success = true
  result.messages_count = #converted_messages
  
  return unified_history, result
end

-- ⚡ Atomic file write with temporary file and rename
---@param filepath string
---@param content string
---@return boolean success
---@return string | nil error
function MigrationEngine:atomic_write(filepath, content)
  local temp_filepath = filepath .. ".tmp"
  local target_file = require("plenary.path"):new(filepath)
  local temp_file = require("plenary.path"):new(temp_filepath)
  
  -- 📝 Write to temporary file
  local write_success, write_error = pcall(function()
    temp_file:write(content, "w")
  end)
  
  if not write_success then
    -- 🧹 Cleanup temp file if it exists
    if temp_file:exists() then
      temp_file:rm()
    end
    return false, "Failed to write temporary file: " .. tostring(write_error)
  end
  
  -- ✅ Validate JSON before rename
  local validate_success, validate_error = pcall(function()
    vim.json.decode(content)
  end)
  
  if not validate_success then
    temp_file:rm()
    return false, "JSON validation failed: " .. tostring(validate_error)
  end
  
  -- 🔄 Atomic rename
  local rename_success, rename_error = pcall(function()
    if target_file:exists() then
      target_file:rm()
    end
    temp_file:rename({ new_name = target_file.filename })
  end)
  
  if not rename_success then
    if temp_file:exists() then
      temp_file:rm()
    end
    return false, "Failed to rename temporary file: " .. tostring(rename_error)
  end
  
  return true, nil
end

-- 📊 Progress reporting for large datasets
---@class MigrationProgress
---@field total integer
---@field completed integer
---@field failed integer
---@field current_file string | nil

-- 📈 Create progress tracker
---@param total integer
---@return MigrationProgress
function M.create_progress(total)
  return {
    total = total,
    completed = 0,
    failed = 0,
    current_file = nil
  }
end

-- 📊 Update progress
---@param progress MigrationProgress
---@param filename string
---@param success boolean
function M.update_progress(progress, filename, success)
  if success then
    progress.completed = progress.completed + 1
  else
    progress.failed = progress.failed + 1
  end
  progress.current_file = filename
end

-- 📄 Get progress report
---@param progress MigrationProgress
---@return string
function M.get_progress_report(progress)
  local percentage = math.floor((progress.completed + progress.failed) / progress.total * 100)
  return string.format(
    "Migration progress: %d%% (%d/%d completed, %d failed)%s",
    percentage,
    progress.completed,
    progress.total,
    progress.failed,
    progress.current_file and (" - Current: " .. progress.current_file) or ""
  )
end

-- 🔧 Enhanced tool processing preservation during migration
-- Extends the collect_tool_info function to handle migrated data properly

---@class MigratedToolInfo : HistoryToolInfo
---@field migrated_from_legacy boolean Whether this tool info was migrated from legacy format
---@field legacy_entry_index integer | nil Original entry index in legacy format
---@field preservation_metadata table<string, any> | nil Additional metadata for preservation

---@class MigratedFileInfo : HistoryFileInfo
---@field migrated_tool_chains table<string, string> | nil Mapping of tool IDs to their chain relationships
---@field legacy_file_references string[] | nil References from legacy selected_file fields

-- 🔍 Enhanced tool info collection for migrated messages
---@param messages avante.HistoryMessage[]
---@param migration_metadata table | nil Metadata from migration process
---@return table<string, MigratedToolInfo>
---@return table<string, MigratedFileInfo>
function M.collect_migrated_tool_info(messages, migration_metadata)
  -- 🚀 Use the existing collect_tool_info function as base
  local History = require("avante.history")
  local base_tools, base_files = History.Helpers and History.collect_tool_info and History.collect_tool_info(messages) or {}, {}
  
  -- 🔄 Enhance with migration-specific information
  local migrated_tools = {}
  local migrated_files = {}
  
  -- 📋 Copy base tool information and enhance
  for tool_id, tool_info in pairs(base_tools) do
    migrated_tools[tool_id] = vim.tbl_extend("force", tool_info, {
      migrated_from_legacy = migration_metadata ~= nil,
      preservation_metadata = migration_metadata and {
        source_version = migration_metadata.source_version,
        target_version = migration_metadata.target_version,
        migrated_at = migration_metadata.migrated_at
      } or nil
    })
  end
  
  -- 📁 Copy base file information and enhance
  for file_path, file_info in pairs(base_files) do
    migrated_files[file_path] = vim.tbl_extend("force", file_info, {
      migrated_tool_chains = {},
      legacy_file_references = {}
    })
  end
  
  -- 🔗 Build tool chains and file references from messages
  for _, message in ipairs(messages) do
    -- 🔍 Check for tool use information
    local use = require("avante.history.helpers").get_tool_use_data(message)
    if use and migrated_tools[use.id] then
      local tool_info = migrated_tools[use.id]
      if tool_info.path then
        local file_info = migrated_files[tool_info.path]
        if file_info then
          file_info.migrated_tool_chains[use.id] = tool_info.kind
        end
      end
    end
    
    -- 📄 Check for legacy file references preserved during migration
    if message.selected_filepaths then
      for _, filepath in ipairs(message.selected_filepaths) do
        local normalized_path = Utils.uniform_path(filepath)
        local file_info = migrated_files[normalized_path]
        if file_info then
          table.insert(file_info.legacy_file_references, filepath)
        else
          -- 🆕 Create new file info for legacy references
          migrated_files[normalized_path] = {
            migrated_tool_chains = {},
            legacy_file_references = { filepath }
          }
        end
      end
    end
  end
  
  return migrated_tools, migrated_files
end

-- 🔄 Preserve tool chain continuity during migration
---@param messages avante.HistoryMessage[]
---@param migration_metadata table Migration metadata
---@return avante.HistoryMessage[] Enhanced messages with preserved tool chains
function M.preserve_tool_chain_continuity(messages, migration_metadata)
  local migrated_tools, migrated_files = M.collect_migrated_tool_info(messages, migration_metadata)
  
  -- 📊 Track tool chain statistics
  local chain_stats = {
    preserved_chains = 0,
    broken_chains = 0,
    synthetic_messages_added = 0,
    file_references_preserved = 0
  }
  
  -- 🔗 Build tool invocation order map
  local tool_order = {}
  for i, message in ipairs(messages) do
    local use = require("avante.history.helpers").get_tool_use_data(message)
    if use and use.id then
      tool_order[use.id] = i
    end
  end
  
  -- 📈 Enhance messages to preserve tool chain continuity
  local enhanced_messages = vim.deepcopy(messages)
  
  -- 🔍 Process each tool to ensure continuity
  for tool_id, tool_info in pairs(migrated_tools) do
    if tool_info.result and tool_info.path then
      local file_info = migrated_files[tool_info.path]
      
      -- ✅ Check if this tool chain is preserved
      if file_info and file_info.last_tool_id == tool_id then
        chain_stats.preserved_chains = chain_stats.preserved_chains + 1
        
        -- 📝 Add synthetic message for tool chain documentation if needed
        if migration_metadata.add_synthetic_documentation then
          local doc_message = Message:new_assistant_synthetic(
            string.format("🔄 Tool chain preserved for %s: %s -> %s", 
              tool_info.path, 
              tool_info.kind, 
              tool_info.result.is_error and "failed" or "succeeded")
          )
          
          -- 📍 Insert after the original tool result
          local insert_position = tool_order[tool_id] and (tool_order[tool_id] + 1) or #enhanced_messages + 1
          table.insert(enhanced_messages, insert_position, doc_message)
          chain_stats.synthetic_messages_added = chain_stats.synthetic_messages_added + 1
        end
      else
        chain_stats.broken_chains = chain_stats.broken_chains + 1
        Utils.debug(string.format("Tool chain broken for %s (tool %s)", tool_info.path or "unknown", tool_id))
      end
      
      -- 📁 Count preserved file references
      if file_info and file_info.legacy_file_references then
        chain_stats.file_references_preserved = chain_stats.file_references_preserved + #file_info.legacy_file_references
      end
    end
  end
  
  -- 📊 Log preservation statistics
  Utils.info(string.format(
    "Tool chain preservation: %d chains preserved, %d broken, %d synthetic messages added, %d file references preserved",
    chain_stats.preserved_chains,
    chain_stats.broken_chains,
    chain_stats.synthetic_messages_added,
    chain_stats.file_references_preserved
  ))
  
  -- 📋 Add preservation statistics to migration metadata
  if migration_metadata then
    migration_metadata.tool_chain_stats = chain_stats
  end
  
  return enhanced_messages
end

-- 🔧 Migrate tool state tracking logic
---@param history avante.ChatHistory
---@param migration_result MigrationResult
---@return avante.ChatHistory Enhanced history with preserved tool state
function M.migrate_tool_state_tracking(history, migration_result)
  if not history.messages then
    return history
  end
  
  -- 🔄 Apply tool chain preservation
  local enhanced_messages = M.preserve_tool_chain_continuity(
    history.messages, 
    history.migration_metadata or {}
  )
  
  -- 📝 Update history with enhanced messages
  local enhanced_history = vim.deepcopy(history)
  enhanced_history.messages = enhanced_messages
  
  -- 📊 Update migration metadata
  if enhanced_history.migration_metadata then
    enhanced_history.migration_metadata.tool_state_preserved = true
    enhanced_history.migration_metadata.enhanced_messages_count = #enhanced_messages
  end
  
  return enhanced_history
end

-- Export the migration engine constructor
M.MigrationEngine = MigrationEngine

return M
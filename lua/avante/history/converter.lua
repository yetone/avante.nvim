local Utils = require("avante.utils")
local Message = require("avante.history.message")
local Migration = require("avante.history.migration")

---@class avante.HistoryConverter
local M = {}

--- 🔄 Enhanced conversion with comprehensive error handling and metadata preservation
---@class avante.ConversionResult
---@field success boolean Whether conversion succeeded
---@field messages avante.HistoryMessage[] Converted messages
---@field errors string[] List of conversion errors
---@field warnings string[] List of conversion warnings
---@field preserved_metadata table Metadata preserved during conversion

--- 🛡️ Validates legacy entry before conversion
---@param entry avante.ChatHistoryEntry Legacy entry to validate
---@param entry_index number Index of entry for error reporting
---@return boolean valid True if entry is valid
---@return string[] issues List of validation issues found
function M.validate_legacy_entry(entry, entry_index)
  local issues = {}
  
  -- ✅ Basic structure validation
  if not entry.timestamp then
    table.insert(issues, string.format("Entry %d missing timestamp", entry_index))
  end
  
  if not entry.provider then
    table.insert(issues, string.format("Entry %d missing provider", entry_index))
  end
  
  if not entry.model then
    table.insert(issues, string.format("Entry %d missing model", entry_index))
  end
  
  -- 📝 Content validation
  if (not entry.request or entry.request == "") and (not entry.response or entry.response == "") then
    table.insert(issues, string.format("Entry %d has no request or response content", entry_index))
  end
  
  -- 🔍 Selected code validation
  if entry.selected_code then
    if not entry.selected_code.path then
      table.insert(issues, string.format("Entry %d selected_code missing path", entry_index))
    end
    if not entry.selected_code.content then
      table.insert(issues, string.format("Entry %d selected_code missing content", entry_index))
    end
  end
  
  return #issues == 0, issues
end

--- 🔧 Enhanced conversion with comprehensive metadata preservation
---@param entry avante.ChatHistoryEntry Legacy entry to convert
---@param entry_index number Index of entry for tracking
---@return avante.ConversionResult result Conversion result with messages and metadata
function M.convert_entry_with_metadata(entry, entry_index)
  local result = {
    success = true,
    messages = {},
    errors = {},
    warnings = {},
    preserved_metadata = {
      entry_index = entry_index,
      original_timestamp = entry.timestamp,
      original_provider = entry.provider,
      original_model = entry.model,
    }
  }
  
  -- 🛡️ Validate entry before conversion
  local valid, issues = M.validate_legacy_entry(entry, entry_index)
  if not valid then
    result.success = false
    result.errors = issues
    return result
  end
  
  -- 🔄 Convert user request if present
  if entry.request and entry.request ~= "" then
    local user_message = Message:new("user", entry.request, {
      timestamp = entry.timestamp,
      is_user_submission = true,
      visible = entry.visible ~= false, -- Default to true if not specified
      selected_filepaths = entry.selected_filepaths,
      selected_code = entry.selected_code,
      provider = entry.provider,
      model = entry.model,
      turn_id = Utils.uuid(), -- Generate unique turn ID for tracking
    })
    
    table.insert(result.messages, user_message)
    Utils.debug(string.format("✅ Converted user request from entry %d", entry_index))
  else
    table.insert(result.warnings, string.format("Entry %d has empty or missing request", entry_index))
  end
  
  -- 🤖 Convert assistant response if present
  if entry.response and entry.response ~= "" then
    local assistant_opts = {
      timestamp = entry.timestamp,
      visible = entry.visible ~= false, -- Default to true if not specified
      provider = entry.provider,
      model = entry.model,
      turn_id = result.messages[#result.messages] and result.messages[#result.messages].turn_id or Utils.uuid(),
    }
    
    -- 📋 Preserve original response if available
    if entry.original_response and entry.original_response ~= entry.response then
      assistant_opts.original_content = entry.original_response
      table.insert(result.warnings, string.format("Entry %d has modified response, preserved original", entry_index))
    end
    
    local assistant_message = Message:new("assistant", entry.response, assistant_opts)
    table.insert(result.messages, assistant_message)
    Utils.debug(string.format("✅ Converted assistant response from entry %d", entry_index))
  else
    table.insert(result.warnings, string.format("Entry %d has empty or missing response", entry_index))
  end
  
  -- 📊 Update preserved metadata with conversion stats
  result.preserved_metadata.messages_created = #result.messages
  result.preserved_metadata.has_selected_code = entry.selected_code ~= nil
  result.preserved_metadata.has_selected_files = entry.selected_filepaths ~= nil and #entry.selected_filepaths > 0
  
  return result
end

--- 🚀 Batch conversion of all legacy entries with comprehensive error handling
---@param history avante.ChatHistory Legacy history data
---@return avante.HistoryMessage[] messages All converted messages
---@return string[] errors List of all conversion errors
---@return string[] warnings List of all conversion warnings
---@return table conversion_stats Statistics about the conversion process
function M.batch_convert_entries(history)
  local all_messages = {}
  local all_errors = {}
  local all_warnings = {}
  local conversion_stats = {
    total_entries = 0,
    successful_conversions = 0,
    failed_conversions = 0,
    messages_created = 0,
    entries_with_selected_code = 0,
    entries_with_selected_files = 0,
  }
  
  if not history.entries or #history.entries == 0 then
    table.insert(all_warnings, "No legacy entries found to convert")
    return all_messages, all_errors, all_warnings, conversion_stats
  end
  
  conversion_stats.total_entries = #history.entries
  
  -- 🔄 Process each entry with comprehensive error handling
  for i, entry in ipairs(history.entries) do
    local conversion_result = M.convert_entry_with_metadata(entry, i)
    
    if conversion_result.success then
      conversion_stats.successful_conversions = conversion_stats.successful_conversions + 1
      conversion_stats.messages_created = conversion_stats.messages_created + #conversion_result.messages
      
      -- 📊 Track metadata statistics
      if conversion_result.preserved_metadata.has_selected_code then
        conversion_stats.entries_with_selected_code = conversion_stats.entries_with_selected_code + 1
      end
      if conversion_result.preserved_metadata.has_selected_files then
        conversion_stats.entries_with_selected_files = conversion_stats.entries_with_selected_files + 1
      end
      
      -- ✅ Add converted messages to result
      for _, message in ipairs(conversion_result.messages) do
        table.insert(all_messages, message)
      end
    else
      conversion_stats.failed_conversions = conversion_stats.failed_conversions + 1
    end
    
    -- 📝 Collect all errors and warnings
    for _, error in ipairs(conversion_result.errors) do
      table.insert(all_errors, error)
    end
    for _, warning in ipairs(conversion_result.warnings) do
      table.insert(all_warnings, warning)
    end
  end
  
  -- 📊 Log conversion summary
  Utils.info(string.format("🔄 Batch conversion completed: %d/%d entries successful, %d messages created", 
                           conversion_stats.successful_conversions, 
                           conversion_stats.total_entries, 
                           conversion_stats.messages_created))
  
  if #all_errors > 0 then
    Utils.warn(string.format("⚠️  %d conversion errors encountered", #all_errors))
  end
  
  if #all_warnings > 0 then
    Utils.debug(string.format("📝 %d conversion warnings generated", #all_warnings))
  end
  
  return all_messages, all_errors, all_warnings, conversion_stats
end

--- 🔗 Preserve tool processing chains during conversion
---@param messages avante.HistoryMessage[] Converted messages to enhance
---@return avante.HistoryMessage[] enhanced_messages Messages with preserved tool chains
function M.preserve_tool_processing_chains(messages)
  local enhanced_messages = {}
  local tool_chain_map = {} -- Track tool invocation sequences
  
  for i, message in ipairs(messages) do
    -- 🔧 Check if message contains tool use or tool result data
    local Helpers = require("avante.history.helpers")
    local tool_use = Helpers.get_tool_use_data(message)
    local tool_result = Helpers.get_tool_result_data(message)
    
    if tool_use then
      -- 📋 Track tool invocation
      tool_chain_map[tool_use.id] = {
        use_message = message,
        use_index = i,
        result_message = nil,
        result_index = nil,
      }
      Utils.debug(string.format("🔧 Tracked tool use: %s (ID: %s)", tool_use.name, tool_use.id))
    elseif tool_result then
      -- 🔗 Link tool result to its invocation
      local chain_info = tool_chain_map[tool_result.tool_use_id]
      if chain_info then
        chain_info.result_message = message
        chain_info.result_index = i
        Utils.debug(string.format("🔗 Linked tool result to use ID: %s", tool_result.tool_use_id))
      else
        Utils.warn(string.format("⚠️  Orphaned tool result found: %s", tool_result.tool_use_id))
      end
    end
    
    table.insert(enhanced_messages, message)
  end
  
  -- 📊 Log tool chain preservation stats
  local complete_chains = 0
  local incomplete_chains = 0
  
  for tool_id, chain_info in pairs(tool_chain_map) do
    if chain_info.result_message then
      complete_chains = complete_chains + 1
    else
      incomplete_chains = incomplete_chains + 1
      Utils.warn(string.format("⚠️  Incomplete tool chain: %s", tool_id))
    end
  end
  
  if complete_chains > 0 or incomplete_chains > 0 then
    Utils.info(string.format("🔗 Tool chain preservation: %d complete, %d incomplete", 
                             complete_chains, incomplete_chains))
  end
  
  return enhanced_messages
end

--- 🎯 Main conversion orchestrator with full error handling
---@param history avante.ChatHistory Legacy history to convert
---@return avante.UnifiedChatHistory converted_history Fully converted history
---@return boolean success True if conversion succeeded
---@return string[] errors List of conversion errors
---@return string[] warnings List of conversion warnings
function M.convert_legacy_history(history)
  Utils.info("🚀 Starting comprehensive legacy history conversion")
  
  -- 🔄 Batch convert all entries
  local messages, errors, warnings, stats = M.batch_convert_entries(history)
  
  -- 🔗 Preserve tool processing chains
  if #messages > 0 then
    messages = M.preserve_tool_processing_chains(messages)
  end
  
  -- 📋 Preserve existing messages if present (hybrid format support)
  if history.messages then
    Utils.info(string.format("📋 Preserving %d existing messages from hybrid format", #history.messages))
    for _, existing_message in ipairs(history.messages) do
      table.insert(messages, existing_message)
    end
  end
  
  -- 🏗️ Build unified history structure
  ---@type avante.UnifiedChatHistory
  local converted_history = {
    title = history.title or "untitled",
    timestamp = history.timestamp,
    filename = history.filename,
    messages = messages,
    todos = history.todos,
    memory = history.memory,
    system_prompt = history.system_prompt,
    tokens_usage = history.tokens_usage,
    version = Migration.CURRENT_VERSION,
    migration_metadata = Migration.create_migration_metadata("ChatHistoryEntry", nil),
  }
  
  -- 📊 Enhanced migration metadata with conversion stats
  converted_history.migration_metadata.conversion_stats = stats
  
  local success = #errors == 0 and stats.failed_conversions == 0
  
  if success then
    Utils.info("🎉 Legacy history conversion completed successfully")
  else
    Utils.error(string.format("❌ Legacy history conversion failed: %d errors", #errors))
  end
  
  return converted_history, success, errors, warnings
end

return M
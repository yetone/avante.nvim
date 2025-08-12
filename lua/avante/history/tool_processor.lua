local Utils = require("avante.utils")
local Helpers = require("avante.history.helpers")
local Message = require("avante.history.message")

---@class avante.ToolProcessor
local M = {}

--- 🛠️ Enhanced tool information with migration metadata
---@class avante.EnhancedHistoryToolInfo : HistoryToolInfo
---@field migration_preserved boolean Whether this tool info was preserved during migration
---@field original_entry_index number | nil Original entry index if migrated from legacy
---@field tool_chain_id string Unique identifier for tool invocation chains
---@field synthetic_messages avante.HistoryMessage[] | nil Generated synthetic messages
---@field processing_errors string[] | nil Errors encountered during tool processing

--- 🔗 Enhanced file information with migration tracking
---@class avante.EnhancedHistoryFileInfo : HistoryFileInfo
---@field migration_preserved boolean Whether this file info was preserved during migration
---@field tool_operations_count number Number of tool operations on this file
---@field last_migration_timestamp string | nil When this file info was last migrated

--- 🔍 Enhanced tool information collection with migration awareness
---@param messages avante.HistoryMessage[]
---@param migration_context table | nil Optional migration context for tracking
---@return table<string, avante.EnhancedHistoryToolInfo> Enhanced tool information map
---@return table<string, avante.EnhancedHistoryFileInfo> Enhanced file information map
---@return table processing_stats Statistics about tool processing
function M.collect_enhanced_tool_info(messages, migration_context)
  ---@type table<string, avante.EnhancedHistoryToolInfo>
  local tools = {}
  ---@type table<string, avante.EnhancedHistoryFileInfo>
  local files = {}
  
  local processing_stats = {
    total_tools = 0,
    tool_uses = 0,
    tool_results = 0,
    orphaned_results = 0,
    file_operations = 0,
    edit_operations = 0,
    view_operations = 0,
    synthetic_messages_generated = 0,
  }
  
  -- 🔍 First pass: collect all tool invocations and build chains
  for i, message in ipairs(messages) do
    local tool_use = Helpers.get_tool_use_data(message)
    if tool_use then
      processing_stats.tool_uses = processing_stats.tool_uses + 1
      processing_stats.total_tools = processing_stats.total_tools + 1
      
      -- 🏗️ Build enhanced tool info
      local enhanced_tool_info = {
        kind = "other",
        use = tool_use,
        result = nil,
        result_message = nil,
        path = nil,
        migration_preserved = migration_context ~= nil,
        original_entry_index = migration_context and migration_context.entry_index or nil,
        tool_chain_id = Utils.uuid(),
        synthetic_messages = {},
        processing_errors = {},
      }
      
      -- 🔧 Determine tool kind and extract path information
      if tool_use.name == "view" or Utils.is_edit_tool_use(tool_use) then
        if tool_use.input and tool_use.input.path then
          enhanced_tool_info.kind = tool_use.name == "view" and "view" or "edit"
          enhanced_tool_info.path = Utils.uniform_path(tool_use.input.path)
          
          if enhanced_tool_info.kind == "view" then
            processing_stats.view_operations = processing_stats.view_operations + 1
          else
            processing_stats.edit_operations = processing_stats.edit_operations + 1
          end
          processing_stats.file_operations = processing_stats.file_operations + 1
        else
          table.insert(enhanced_tool_info.processing_errors, "Tool missing path information")
          Utils.warn(string.format("⚠️  Tool %s missing path information", tool_use.name))
        end
      end
      
      tools[tool_use.id] = enhanced_tool_info
      Utils.debug(string.format("🔧 Enhanced tool info created for %s (ID: %s)", tool_use.name, tool_use.id))
    end
  end
  
  -- 🔗 Second pass: link tool results and build file information
  for i, message in ipairs(messages) do
    local tool_result = Helpers.get_tool_result_data(message)
    if tool_result then
      processing_stats.tool_results = processing_stats.tool_results + 1
      
      local tool_info = tools[tool_result.tool_use_id]
      if tool_info then
        -- 🔗 Link result to tool use
        tool_info.result = tool_result
        tool_info.result_message = message
        
        -- 📁 Update file information if this tool operates on a file
        if tool_info.path then
          local file_info = files[tool_info.path]
          if not file_info then
            file_info = {
              last_tool_id = nil,
              edit_tool_id = nil,
              migration_preserved = migration_context ~= nil,
              tool_operations_count = 0,
              last_migration_timestamp = migration_context and Utils.get_timestamp() or nil,
            }
            files[tool_info.path] = file_info
          end
          
          file_info.tool_operations_count = file_info.tool_operations_count + 1
          file_info.last_tool_id = tool_result.tool_use_id
          
          -- 📝 Track successful edit operations
          if tool_info.kind == "edit" and not (tool_result.is_error or tool_result.is_user_declined) then
            file_info.edit_tool_id = tool_result.tool_use_id
          end
        end
        
        Utils.debug(string.format("🔗 Linked tool result to use %s", tool_result.tool_use_id))
      else
        processing_stats.orphaned_results = processing_stats.orphaned_results + 1
        Utils.warn(string.format("⚠️  Orphaned tool result found: %s", tool_result.tool_use_id))
      end
    end
  end
  
  -- 📊 Log processing statistics
  Utils.info(string.format("🛠️  Tool processing stats: %d uses, %d results, %d file ops", 
                           processing_stats.tool_uses, 
                           processing_stats.tool_results, 
                           processing_stats.file_operations))
  
  if processing_stats.orphaned_results > 0 then
    Utils.warn(string.format("⚠️  Found %d orphaned tool results", processing_stats.orphaned_results))
  end
  
  return tools, files, processing_stats
end

--- 🎭 Generate enhanced synthetic messages with migration context
---@param tool_info avante.EnhancedHistoryToolInfo Tool information
---@param file_info avante.EnhancedHistoryFileInfo | nil File information if applicable
---@return avante.HistoryMessage[] synthetic_messages Generated synthetic messages
function M.generate_enhanced_synthetic_messages(tool_info, file_info)
  local synthetic_messages = {}
  
  if tool_info.kind == "edit" and tool_info.path then
    -- 🔍 Generate post-edit view messages with enhanced context
    local view_messages = M.generate_post_edit_view_messages(tool_info, file_info)
    for _, msg in ipairs(view_messages) do
      table.insert(synthetic_messages, msg)
    end
    
    -- 🩺 Generate diagnostic messages with migration awareness
    if not (tool_info.result and (tool_info.result.is_error or tool_info.result.is_user_declined)) then
      local diagnostic_messages = M.generate_enhanced_diagnostic_messages(tool_info.path, tool_info)
      for _, msg in ipairs(diagnostic_messages) do
        table.insert(synthetic_messages, msg)
      end
    end
  end
  
  -- 📋 Add migration metadata to synthetic messages
  for _, msg in ipairs(synthetic_messages) do
    msg.migration_preserved = true
    msg.synthetic_source = tool_info.tool_chain_id
  end
  
  tool_info.synthetic_messages = synthetic_messages
  return synthetic_messages
end

--- 👀 Generate post-edit view messages with enhanced context
---@param tool_info avante.EnhancedHistoryToolInfo Tool information
---@param file_info avante.EnhancedHistoryFileInfo | nil File information
---@return avante.HistoryMessage[] view_messages Generated view messages
function M.generate_post_edit_view_messages(tool_info, file_info)
  local path = tool_info.path
  local tool_use = tool_info.use
  
  -- 🔍 Determine if this is a stale view (not the latest operation on the file)
  local is_stale = file_info and tool_use.id ~= file_info.last_tool_id
  
  -- 📝 Generate contextual description with migration awareness
  local context_desc = string.format("Viewing file %s after edit operation", path)
  if tool_info.migration_preserved then
    context_desc = context_desc .. " (preserved during migration)"
  end
  if is_stale then
    context_desc = context_desc .. " (may be stale, superseded by later operations)"
  end
  
  local view_result, view_error
  if is_stale then
    view_result = string.format("The file %s has been updated by subsequent operations. Please use the latest `view` tool result!", path)
  else
    -- 🔍 Get current file content
    view_result, view_error = require("avante.llm_tools.view").func({ path = path }, {})
  end
  
  if view_error then 
    view_result = "Error: " .. view_error 
  end
  
  -- 🆔 Generate consistent tool identifiers
  local view_tool_use_id = Utils.uuid()
  local view_tool_name = "view"
  local view_tool_input = { path = path }
  
  -- 🔧 Handle different edit tool types
  if tool_use.name == "str_replace_editor" and tool_use.input.command == "str_replace" then
    view_tool_name = "str_replace_editor"
    view_tool_input.command = "view"
  elseif tool_use.name == "str_replace_based_edit_tool" and tool_use.input.command == "str_replace" then
    view_tool_name = "str_replace_based_edit_tool"
    view_tool_input.command = "view"
  end
  
  return {
    Message:new_assistant_synthetic(context_desc),
    Message:new_assistant_synthetic({
      type = "tool_use",
      id = view_tool_use_id,
      name = view_tool_name,
      input = view_tool_input,
    }),
    Message:new_user_synthetic({
      type = "tool_result",
      tool_use_id = view_tool_use_id,
      content = view_result,
      is_error = view_error ~= nil,
      is_user_declined = false,
    }),
  }
end

--- 🩺 Generate enhanced diagnostic messages with migration context
---@param path string File path
---@param tool_info avante.EnhancedHistoryToolInfo Tool information
---@return avante.HistoryMessage[] diagnostic_messages Generated diagnostic messages
function M.generate_enhanced_diagnostic_messages(path, tool_info)
  local diagnostic_tool_use_id = Utils.uuid()
  local diagnostics = Utils.lsp.get_diagnostics_from_filepath(path)
  
  -- 📝 Enhanced diagnostic description with migration context
  local diagnostic_desc = string.format("Checking for errors after editing %s", path)
  if tool_info.migration_preserved then
    diagnostic_desc = diagnostic_desc .. " (tool operation preserved from migration)"
  end
  
  return {
    Message:new_assistant_synthetic(diagnostic_desc),
    Message:new_assistant_synthetic({
      type = "tool_use",
      id = diagnostic_tool_use_id,
      name = "get_diagnostics",
      input = { path = path },
    }),
    Message:new_user_synthetic({
      type = "tool_result",
      tool_use_id = diagnostic_tool_use_id,
      content = vim.json.encode(diagnostics),
      is_error = false,
      is_user_declined = false,
    }),
  }
end

--- 🔄 Enhanced history refresh with migration-aware processing
---@param messages avante.HistoryMessage[]
---@param tools table<string, avante.EnhancedHistoryToolInfo>
---@param files table<string, avante.EnhancedHistoryFileInfo>
---@param add_diagnostic boolean
---@param tools_to_text integer
---@param migration_context table | nil
---@return avante.HistoryMessage[] refreshed_messages
function M.refresh_history_with_migration_context(messages, tools, files, add_diagnostic, tools_to_text, migration_context)
  ---@type avante.HistoryMessage[]
  local updated_messages = {}
  local tool_count = 0
  local synthetic_messages_added = 0
  
  for _, message in ipairs(messages) do
    local tool_use = Helpers.get_tool_use_data(message)
    if tool_use then
      local tool_info = tools[tool_use.id]
      if not tool_info or not tool_info.result then 
        goto continue 
      end
      
      if tool_count < tools_to_text then
        -- 📝 Convert old tool invocations to text for compactness
        local text_msgs = M.convert_tool_to_enhanced_text(tool_info, migration_context)
        updated_messages = vim.list_extend(updated_messages, text_msgs)
        Utils.debug(string.format("📝 Converted tool %s to %d text messages", tool_use.name, #text_msgs))
      else
        -- 🔧 Keep tool invocation and result as-is
        table.insert(updated_messages, message)
        table.insert(updated_messages, tool_info.result_message)
        tool_count = tool_count + 1
        
        -- 👀 Update view results with latest content
        if tool_info.kind == "view" then
          M.update_view_result_with_migration_context(tool_info, files[tool_info.path], migration_context)
        end
      end
      
      -- 🎭 Generate synthetic messages for edit operations
      if tool_info.kind == "edit" and tool_info.path then
        local file_info = files[tool_info.path]
        local synthetic_msgs = M.generate_enhanced_synthetic_messages(tool_info, file_info)
        updated_messages = vim.list_extend(updated_messages, synthetic_msgs)
        synthetic_messages_added = synthetic_messages_added + #synthetic_msgs
        
        Utils.debug(string.format("🎭 Added %d synthetic messages for edit on %s", #synthetic_msgs, tool_info.path))
      end
      
    elseif not Helpers.get_tool_result_data(message) then
      -- 📋 Keep non-tool messages as-is
      table.insert(updated_messages, message)
    end
    
    ::continue::
  end
  
  Utils.info(string.format("🔄 History refresh completed: %d synthetic messages added", synthetic_messages_added))
  return updated_messages
end

--- 📝 Convert tool to enhanced text with migration context
---@param tool_info avante.EnhancedHistoryToolInfo Tool information
---@param migration_context table | nil Migration context
---@return avante.HistoryMessage[] text_messages Converted text messages
function M.convert_tool_to_enhanced_text(tool_info, migration_context)
  local context_suffix = ""
  if migration_context then
    context_suffix = " (preserved from legacy format)"
  end
  
  local success_text = "successful"
  if tool_info.result and (tool_info.result.is_error or tool_info.result.is_user_declined) then
    success_text = "failed"
  end
  
  return {
    Message:new_assistant_synthetic(
      string.format("Tool use %s(%s)%s", tool_info.use.name, vim.json.encode(tool_info.use.input), context_suffix)
    ),
    Message:new_user_synthetic({
      type = "text",
      text = string.format("Tool use [%s] was %s%s", tool_info.use.name, success_text, context_suffix),
    }),
  }
end

--- 👀 Update view result with migration context
---@param tool_info avante.EnhancedHistoryToolInfo Tool information
---@param file_info avante.EnhancedHistoryFileInfo | nil File information
---@param migration_context table | nil Migration context
function M.update_view_result_with_migration_context(tool_info, file_info, migration_context)
  local use = tool_info.use
  local result = tool_info.result
  
  if not result then return end
  
  -- 🔍 Determine if view is stale
  local is_stale = file_info and use.id ~= file_info.last_tool_id
  
  if is_stale then
    result.content = string.format("The file %s has been updated. Please use the latest `view` tool result!", tool_info.path)
    if migration_context then
      result.content = result.content .. " (Note: This view was preserved during migration and may be outdated)"
    end
  else
    -- 🔍 Get current file content
    local view_result, view_error = require("avante.llm_tools.view").func(
      { path = tool_info.path, start_line = use.input.start_line, end_line = use.input.end_line },
      {}
    )
    result.content = view_error and ("Error: " .. view_error) or view_result
    result.is_error = view_error ~= nil
    
    if migration_context and not view_error then
      -- 📝 Add migration context note to successful views
      result.content = result.content .. "\n\n-- Note: File content refreshed after migration --"
    end
  end
end

--- 🎯 Main enhanced tool processing function with migration support
---@param messages avante.HistoryMessage[]
---@param max_tool_use integer | nil
---@param add_diagnostic boolean
---@param migration_context table | nil
---@return avante.HistoryMessage[] processed_messages
function M.process_tools_with_migration_context(messages, max_tool_use, add_diagnostic, migration_context)
  Utils.info("🛠️  Starting enhanced tool processing with migration context")
  
  -- 🔍 Collect enhanced tool information
  local tools, files, stats = M.collect_enhanced_tool_info(messages, migration_context)
  
  -- 📊 Calculate tools to convert to text
  local tools_to_text = 0
  if max_tool_use then
    local expected_synthetic = stats.edit_operations * (add_diagnostic and 2 or 1)
    local total_expected = stats.total_tools + expected_synthetic
    tools_to_text = math.max(0, total_expected - max_tool_use)
  end
  
  -- 🔄 Process and refresh history
  local processed_messages = M.refresh_history_with_migration_context(
    messages, tools, files, add_diagnostic, tools_to_text, migration_context
  )
  
  Utils.info(string.format("✅ Enhanced tool processing completed: %d messages processed", #processed_messages))
  return processed_messages
end

return M
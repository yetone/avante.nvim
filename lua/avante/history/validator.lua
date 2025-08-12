local Utils = require("avante.utils")
local Helpers = require("avante.history.helpers")
local Migration = require("avante.history.migration")
local Path = require("plenary.path")

---@class avante.HistoryValidator
local M = {}

--- 🎯 Validation severity levels
M.SEVERITY = {
  ERROR = "error",
  WARNING = "warning", 
  INFO = "info"
}

--- 📊 Comprehensive validation result
---@class avante.ValidationResult
---@field is_valid boolean Overall validation status
---@field severity_counts table<string, number> Count of issues by severity
---@field issues avante.ValidationIssue[] List of all validation issues
---@field metadata_checks table Results of metadata validation checks
---@field content_checks table Results of content validation checks
---@field integrity_checks table Results of integrity validation checks
---@field performance_metrics table Performance metrics from validation

--- 🔍 Individual validation issue
---@class avante.ValidationIssue
---@field type string Issue type identifier
---@field severity string Severity level (error/warning/info)
---@field message string Human-readable issue description
---@field details table Additional context and details
---@field suggested_fix string | nil Suggested resolution
---@field location string | nil Location where issue was found

--- 🔧 Core history structure validation
---@param history avante.ChatHistory | avante.UnifiedChatHistory History to validate
---@return avante.ValidationIssue[] issues List of structure validation issues
function M.validate_structure(history)
  local issues = {}
  
  -- ✅ Basic required fields
  if not history.title then
    table.insert(issues, {
      type = "missing_title",
      severity = M.SEVERITY.WARNING,
      message = "History missing title field",
      details = { field = "title" },
      suggested_fix = "Add a default title like 'untitled'",
    })
  end
  
  if not history.timestamp then
    table.insert(issues, {
      type = "missing_timestamp", 
      severity = M.SEVERITY.WARNING,
      message = "History missing timestamp field",
      details = { field = "timestamp" },
      suggested_fix = "Add creation timestamp",
    })
  end
  
  if not history.filename then
    table.insert(issues, {
      type = "missing_filename",
      severity = M.SEVERITY.ERROR,
      message = "History missing filename field",
      details = { field = "filename" },
      suggested_fix = "Set filename based on file path",
    })
  end
  
  -- 🔄 Format-specific validations
  local has_entries = history.entries and #history.entries > 0
  local has_messages = history.messages and #history.messages > 0
  local has_version = history.version ~= nil
  
  if not has_entries and not has_messages then
    table.insert(issues, {
      type = "no_content",
      severity = M.SEVERITY.ERROR,
      message = "History has neither entries nor messages",
      details = { 
        has_entries = has_entries,
        has_messages = has_messages
      },
      suggested_fix = "History must contain either entries (legacy) or messages (unified)",
    })
  end
  
  -- 🎯 Version consistency checks
  if has_version and history.version >= Migration.CURRENT_VERSION then
    if not has_messages then
      table.insert(issues, {
        type = "version_mismatch",
        severity = M.SEVERITY.ERROR,
        message = string.format("Version %d history missing messages field", history.version),
        details = { 
          version = history.version,
          expected_version = Migration.CURRENT_VERSION
        },
        suggested_fix = "Ensure unified format has messages array",
      })
    end
    
    if has_entries and not history.migration_metadata then
      table.insert(issues, {
        type = "missing_migration_metadata",
        severity = M.SEVERITY.WARNING,
        message = "Unified format missing migration metadata despite having entries",
        details = { version = history.version },
        suggested_fix = "Add migration metadata for tracking purposes",
      })
    end
  end
  
  return issues
end

--- 📋 Message content validation
---@param messages avante.HistoryMessage[] Messages to validate
---@return avante.ValidationIssue[] issues List of message validation issues
function M.validate_messages(messages)
  local issues = {}
  local message_uuids = {}
  local turn_id_counts = {}
  
  for i, message in ipairs(messages) do
    local location = string.format("message[%d]", i)
    
    -- 🆔 UUID uniqueness validation
    if message.uuid then
      if message_uuids[message.uuid] then
        table.insert(issues, {
          type = "duplicate_uuid",
          severity = M.SEVERITY.ERROR,
          message = "Duplicate message UUID found",
          details = { 
            uuid = message.uuid,
            first_occurrence = message_uuids[message.uuid],
            current_index = i
          },
          location = location,
          suggested_fix = "Generate new UUID for duplicate message",
        })
      else
        message_uuids[message.uuid] = i
      end
    else
      table.insert(issues, {
        type = "missing_uuid",
        severity = M.SEVERITY.WARNING,
        message = "Message missing UUID",
        details = { message_index = i },
        location = location,
        suggested_fix = "Generate UUID for message tracking",
      })
    end
    
    -- 🎭 Role validation
    if not message.message or not message.message.role then
      table.insert(issues, {
        type = "missing_role",
        severity = M.SEVERITY.ERROR,
        message = "Message missing role field",
        details = { message_index = i },
        location = location,
        suggested_fix = "Set role to 'user' or 'assistant'",
      })
    elseif message.message.role ~= "user" and message.message.role ~= "assistant" then
      table.insert(issues, {
        type = "invalid_role",
        severity = M.SEVERITY.ERROR,
        message = string.format("Invalid role '%s'", message.message.role),
        details = { 
          role = message.message.role,
          message_index = i 
        },
        location = location,
        suggested_fix = "Role must be 'user' or 'assistant'",
      })
    end
    
    -- 📝 Content validation
    if not message.message.content then
      table.insert(issues, {
        type = "missing_content",
        severity = M.SEVERITY.ERROR,
        message = "Message missing content field",
        details = { message_index = i },
        location = location,
        suggested_fix = "Add content to message",
      })
    elseif type(message.message.content) == "string" and message.message.content == "" then
      table.insert(issues, {
        type = "empty_content",
        severity = M.SEVERITY.WARNING,
        message = "Message has empty content",
        details = { message_index = i },
        location = location,
        suggested_fix = "Remove empty messages or add meaningful content",
      })
    end
    
    -- 🔄 Turn ID analysis
    if message.turn_id then
      turn_id_counts[message.turn_id] = (turn_id_counts[message.turn_id] or 0) + 1
    end
  end
  
  -- 📊 Turn ID distribution analysis
  local single_message_turns = 0
  for turn_id, count in pairs(turn_id_counts) do
    if count == 1 then
      single_message_turns = single_message_turns + 1
    end
  end
  
  if single_message_turns > #messages * 0.7 then -- More than 70% single-message turns
    table.insert(issues, {
      type = "fragmented_turns",
      severity = M.SEVERITY.INFO,
      message = "High number of single-message turns detected",
      details = { 
        single_turns = single_message_turns,
        total_messages = #messages,
        percentage = math.floor(single_message_turns / #messages * 100)
      },
      suggested_fix = "Consider consolidating related messages into turns",
    })
  end
  
  return issues
end

--- 🛠️ Tool processing validation
---@param messages avante.HistoryMessage[] Messages to validate for tool processing
---@return avante.ValidationIssue[] issues List of tool processing validation issues
function M.validate_tool_processing(messages)
  local issues = {}
  local tool_uses = {}
  local tool_results = {}
  local orphaned_results = 0
  local incomplete_tools = 0
  
  -- 🔍 Collect tool invocations and results
  for i, message in ipairs(messages) do
    local tool_use = Helpers.get_tool_use_data(message)
    local tool_result = Helpers.get_tool_result_data(message)
    
    if tool_use then
      tool_uses[tool_use.id] = {
        message = message,
        index = i,
        has_result = false,
        tool_name = tool_use.name,
      }
    end
    
    if tool_result then
      tool_results[tool_result.tool_use_id] = {
        message = message,
        index = i,
        has_use = false,
      }
      
      if tool_uses[tool_result.tool_use_id] then
        tool_uses[tool_result.tool_use_id].has_result = true
        tool_results[tool_result.tool_use_id].has_use = true
      else
        orphaned_results = orphaned_results + 1
      end
    end
  end
  
  -- 🔍 Validate tool completeness
  for tool_id, tool_info in pairs(tool_uses) do
    if not tool_info.has_result then
      incomplete_tools = incomplete_tools + 1
      table.insert(issues, {
        type = "incomplete_tool_use",
        severity = M.SEVERITY.WARNING,
        message = string.format("Tool use '%s' missing result", tool_info.tool_name),
        details = {
          tool_id = tool_id,
          tool_name = tool_info.tool_name,
          message_index = tool_info.index,
        },
        location = string.format("message[%d]", tool_info.index),
        suggested_fix = "Ensure all tool uses have corresponding results",
      })
    end
  end
  
  -- 🔍 Report orphaned results
  if orphaned_results > 0 then
    table.insert(issues, {
      type = "orphaned_tool_results",
      severity = M.SEVERITY.ERROR,
      message = string.format("%d tool results without corresponding uses", orphaned_results),
      details = { orphaned_count = orphaned_results },
      suggested_fix = "Remove orphaned tool results or add missing tool uses",
    })
  end
  
  -- 📊 Tool processing health metrics
  local total_tools = vim.tbl_count(tool_uses)
  if total_tools > 0 then
    local completion_rate = (total_tools - incomplete_tools) / total_tools
    if completion_rate < 0.8 then -- Less than 80% completion
      table.insert(issues, {
        type = "low_tool_completion",
        severity = M.SEVERITY.WARNING,
        message = string.format("Low tool completion rate: %.1f%%", completion_rate * 100),
        details = {
          completed_tools = total_tools - incomplete_tools,
          total_tools = total_tools,
          completion_rate = completion_rate,
        },
        suggested_fix = "Review incomplete tool invocations",
      })
    end
  end
  
  return issues
end

--- 🔄 Migration metadata validation
---@param history avante.UnifiedChatHistory History with migration metadata
---@return avante.ValidationIssue[] issues List of migration validation issues
function M.validate_migration_metadata(history)
  local issues = {}
  
  if not history.migration_metadata then
    return issues -- Not a migrated history, no validation needed
  end
  
  local metadata = history.migration_metadata
  
  -- ✅ Required migration fields
  local required_fields = {
    "version", "format", "migrated_at", "original_format", "migration_uuid"
  }
  
  for _, field in ipairs(required_fields) do
    if not metadata[field] then
      table.insert(issues, {
        type = "missing_migration_field",
        severity = M.SEVERITY.WARNING,
        message = string.format("Migration metadata missing %s field", field),
        details = { missing_field = field },
        suggested_fix = "Ensure all required migration fields are present",
      })
    end
  end
  
  -- 🎯 Version consistency
  if metadata.version and metadata.version ~= history.version then
    table.insert(issues, {
      type = "version_inconsistency",
      severity = M.SEVERITY.ERROR,
      message = "Migration metadata version doesn't match history version",
      details = {
        metadata_version = metadata.version,
        history_version = history.version,
      },
      suggested_fix = "Synchronize version fields",
    })
  end
  
  -- 📊 Conversion statistics validation
  if metadata.conversion_stats then
    local stats = metadata.conversion_stats
    if stats.failed_conversions and stats.failed_conversions > 0 then
      table.insert(issues, {
        type = "migration_conversion_failures",
        severity = M.SEVERITY.ERROR,
        message = string.format("%d conversion failures during migration", stats.failed_conversions),
        details = stats,
        suggested_fix = "Review failed conversions and re-migrate if necessary",
      })
    end
    
    if stats.total_entries and stats.messages_created then
      local expected_messages = stats.total_entries * 2 -- Rough estimate: request + response
      local actual_messages = history.messages and #history.messages or 0
      local message_variance = math.abs(actual_messages - stats.messages_created) / math.max(1, stats.messages_created)
      
      if message_variance > 0.2 then -- More than 20% variance
        table.insert(issues, {
          type = "message_count_variance",
          severity = M.SEVERITY.WARNING,
          message = "Significant variance in expected vs actual message count",
          details = {
            expected_from_stats = stats.messages_created,
            actual_count = actual_messages,
            variance_percentage = math.floor(message_variance * 100),
          },
          suggested_fix = "Verify message conversion accuracy",
        })
      end
    end
  end
  
  return issues
end

--- 🎯 Comprehensive history validation
---@param history avante.ChatHistory | avante.UnifiedChatHistory History to validate
---@param filepath string | nil File path for additional context
---@return avante.ValidationResult result Comprehensive validation result
function M.validate_history(history, filepath)
  local start_time = vim.loop.hrtime()
  
  local result = {
    is_valid = true,
    severity_counts = {
      [M.SEVERITY.ERROR] = 0,
      [M.SEVERITY.WARNING] = 0,
      [M.SEVERITY.INFO] = 0,
    },
    issues = {},
    metadata_checks = {},
    content_checks = {},
    integrity_checks = {},
    performance_metrics = {},
  }
  
  -- 🔧 Structure validation
  local structure_issues = M.validate_structure(history)
  result.metadata_checks.structure_validation = {
    issues_count = #structure_issues,
    passed = #structure_issues == 0,
  }
  
  -- 📋 Message validation  
  local messages = require("avante.history").get_history_messages(history)
  local message_issues = M.validate_messages(messages)
  result.content_checks.message_validation = {
    issues_count = #message_issues,
    passed = #message_issues == 0,
    message_count = #messages,
  }
  
  -- 🛠️ Tool processing validation
  local tool_issues = M.validate_tool_processing(messages)
  result.integrity_checks.tool_validation = {
    issues_count = #tool_issues,
    passed = #tool_issues == 0,
  }
  
  -- 🔄 Migration metadata validation (if applicable)
  local migration_issues = {}
  if history.version and history.version >= Migration.CURRENT_VERSION then
    migration_issues = M.validate_migration_metadata(history)
    result.metadata_checks.migration_validation = {
      issues_count = #migration_issues,
      passed = #migration_issues == 0,
      is_migrated = history.migration_metadata ~= nil,
    }
  end
  
  -- 📊 Aggregate all issues
  local all_issue_sets = {
    structure_issues,
    message_issues, 
    tool_issues,
    migration_issues,
  }
  
  for _, issue_set in ipairs(all_issue_sets) do
    for _, issue in ipairs(issue_set) do
      table.insert(result.issues, issue)
      result.severity_counts[issue.severity] = result.severity_counts[issue.severity] + 1
    end
  end
  
  -- 🎯 Determine overall validity
  result.is_valid = result.severity_counts[M.SEVERITY.ERROR] == 0
  
  -- ⚡ Performance metrics
  local end_time = vim.loop.hrtime()
  result.performance_metrics = {
    validation_duration_ms = (end_time - start_time) / 1000000,
    total_issues = #result.issues,
    messages_validated = #messages,
    filepath = filepath,
  }
  
  return result
end

--- 📊 Generate validation report
---@param result avante.ValidationResult Validation result
---@return string report Formatted validation report
function M.generate_report(result)
  local report = {}
  
  -- 📋 Header
  table.insert(report, "🔍 Avante History Validation Report")
  table.insert(report, string.format("   Overall Status: %s", result.is_valid and "✅ VALID" or "❌ INVALID"))
  table.insert(report, string.format("   Validation Time: %.2fms", result.performance_metrics.validation_duration_ms))
  table.insert(report, "")
  
  -- 📊 Summary statistics
  table.insert(report, "📊 Issue Summary:")
  table.insert(report, string.format("   Errors: %d", result.severity_counts.error))
  table.insert(report, string.format("   Warnings: %d", result.severity_counts.warning))
  table.insert(report, string.format("   Info: %d", result.severity_counts.info))
  table.insert(report, "")
  
  -- 🔍 Detailed issues
  if #result.issues > 0 then
    table.insert(report, "🔍 Detailed Issues:")
    for _, issue in ipairs(result.issues) do
      local severity_icon = {
        error = "❌",
        warning = "⚠️ ",
        info = "ℹ️ "
      }
      
      table.insert(report, string.format("   %s %s", severity_icon[issue.severity], issue.message))
      if issue.location then
        table.insert(report, string.format("      Location: %s", issue.location))
      end
      if issue.suggested_fix then
        table.insert(report, string.format("      Fix: %s", issue.suggested_fix))
      end
      table.insert(report, "")
    end
  else
    table.insert(report, "✅ No validation issues found!")
  end
  
  return table.concat(report, "\n")
end

--- 🧪 Batch validation for multiple history files
---@param directory_path string Directory containing history files
---@return table batch_results Results for all validated files
function M.batch_validate_directory(directory_path)
  local batch_results = {
    total_files = 0,
    valid_files = 0,
    invalid_files = 0,
    total_issues = 0,
    file_results = {},
    performance_summary = {
      total_validation_time_ms = 0,
      average_validation_time_ms = 0,
    }
  }
  
  local dir = Path:new(directory_path)
  if not dir:exists() then
    return batch_results
  end
  
  local files = vim.fn.glob(tostring(dir:joinpath("*.json")), false, true)
  local start_time = vim.loop.hrtime()
  
  for _, filepath in ipairs(files) do
    if not filepath:match("metadata.json") then
      batch_results.total_files = batch_results.total_files + 1
      
      local ok, history = pcall(function()
        local content = Path:new(filepath):read()
        return vim.json.decode(content)
      end)
      
      if ok and history then
        local validation_result = M.validate_history(history, filepath)
        
        batch_results.file_results[filepath] = validation_result
        batch_results.total_issues = batch_results.total_issues + #validation_result.issues
        
        if validation_result.is_valid then
          batch_results.valid_files = batch_results.valid_files + 1
        else
          batch_results.invalid_files = batch_results.invalid_files + 1
        end
      else
        -- 📝 Record parsing failure
        batch_results.invalid_files = batch_results.invalid_files + 1
        batch_results.file_results[filepath] = {
          is_valid = false,
          parsing_error = true,
          issues = {{
            type = "parsing_error",
            severity = M.SEVERITY.ERROR,
            message = "Failed to parse history file",
            details = { filepath = filepath },
          }},
        }
      end
    end
  end
  
  local end_time = vim.loop.hrtime()
  batch_results.performance_summary.total_validation_time_ms = (end_time - start_time) / 1000000
  batch_results.performance_summary.average_validation_time_ms = batch_results.total_files > 0 
    and batch_results.performance_summary.total_validation_time_ms / batch_results.total_files 
    or 0
  
  Utils.info(string.format("🧪 Batch validation completed: %d/%d files valid, %d total issues", 
                           batch_results.valid_files, 
                           batch_results.total_files, 
                           batch_results.total_issues))
  
  return batch_results
end

return M
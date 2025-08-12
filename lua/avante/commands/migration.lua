-- 🔧 User-facing migration utilities and commands for Avante history storage system

local Migration = require("avante.history.migration")
local Path = require("avante.path")
local Utils = require("avante.utils")

---@class avante.MigrationCommands
local M = {}

---Migrates a specific history file
---@param bufnr integer Buffer number
---@param filename string History filename to migrate
---@param options? table Migration options
function M.migrate_file(bufnr, filename, options)
  local filepath = Path.history.get_filepath(bufnr, filename)
  
  if not filepath:exists() then
    Utils.error("History file not found: " .. filename)
    return
  end
  
  options = vim.tbl_extend("force", { 
    create_backup = true, 
    validate_integrity = true 
  }, options or {})
  
  Utils.info("🔄 Starting migration for " .. filename .. "...")
  
  local success, error_msg, stats = Migration.migrate_history_file(filepath, options)
  
  if success then
    if stats and stats.already_migrated then
      Utils.info("✅ " .. filename .. " already in unified format")
    else
      Utils.info("🎉 Successfully migrated " .. filename)
      if stats then
        Utils.info(string.format("📊 Migration stats: %d entries → %d messages", 
          stats.entries_processed or 0, stats.messages_created or 0))
      end
    end
  else
    Utils.error("❌ Migration failed for " .. filename .. ": " .. (error_msg or "Unknown error"))
  end
end

---Migrates all history files for a buffer
---@param bufnr integer Buffer number
---@param options? table Migration options with progress callback
function M.migrate_all_for_buffer(bufnr, options)
  options = options or {}
  
  -- 📊 Add progress callback if not provided
  if not options.progress_callback then
    options.progress_callback = function(current, total, message)
      Utils.info(string.format("🔄 [%d/%d] %s", current, total, message))
    end
  end
  
  local results = Path.history.migrate_all(bufnr, options)
  
  -- 🎉 Display summary
  Utils.info("🏁 Migration Summary:")
  Utils.info("   Total files: " .. results.total_files)
  Utils.info("   ✅ Migrated: " .. results.migrated)
  Utils.info("   ⭐ Already unified: " .. results.already_migrated)
  Utils.info("   ❌ Failed: " .. results.failed)
  
  if results.failed > 0 then
    Utils.info("🚨 Failed migrations:")
    for _, error_info in ipairs(results.errors) do
      Utils.error("   " .. error_info.file .. ": " .. error_info.error)
    end
  end
  
  return results
end

---Shows migration status for current buffer
---@param bufnr integer Buffer number
function M.show_migration_status(bufnr)
  local histories = Path.history.list(bufnr)
  
  if #histories == 0 then
    Utils.info("📁 No history files found for current buffer")
    return
  end
  
  local unified_count = 0
  local legacy_count = 0
  local unknown_count = 0
  
  Utils.info("📊 History Format Status:")
  Utils.info("=" .. string.rep("=", 50))
  
  for _, history in ipairs(histories) do
    local status_icon, format_name
    
    if Migration.is_unified_format(history) then
      unified_count = unified_count + 1
      status_icon = "✅"
      format_name = "Unified"
    elseif Migration.is_legacy_format(history) then
      legacy_count = legacy_count + 1
      status_icon = "🔄"
      format_name = "Legacy (needs migration)"
    else
      unknown_count = unknown_count + 1
      status_icon = "❓"
      format_name = "Unknown format"
    end
    
    local message_count = history.messages and #history.messages or #(history.entries or {})
    Utils.info(string.format("   %s %s (%d messages) - %s", 
      status_icon, history.filename, message_count, format_name))
  end
  
  Utils.info("=" .. string.rep("=", 50))
  Utils.info(string.format("📈 Summary: %d unified, %d legacy, %d unknown", 
    unified_count, legacy_count, unknown_count))
  
  if legacy_count > 0 then
    Utils.info("💡 Run :AvanteMigrateAll to migrate legacy histories")
  end
end

---Validates integrity of migrated histories
---@param bufnr integer Buffer number
---@param filename? string Optional specific filename to validate
function M.validate_integrity(bufnr, filename)
  local histories_to_check = {}
  
  if filename then
    local filepath = Path.history.get_filepath(bufnr, filename)
    if filepath:exists() then
      local content = filepath:read()
      if content then
        local history = vim.json.decode(content)
        history.filename = filename
        table.insert(histories_to_check, history)
      end
    else
      Utils.error("History file not found: " .. filename)
      return
    end
  else
    histories_to_check = Path.history.list(bufnr)
  end
  
  if #histories_to_check == 0 then
    Utils.info("📁 No histories found to validate")
    return
  end
  
  Utils.info("🔍 Starting integrity validation...")
  local total_validated = 0
  local total_errors = 0
  local total_warnings = 0
  
  for _, history in ipairs(histories_to_check) do
    if Migration.is_unified_format(history) then
      local valid, errors, details = Migration.validate_migrated_history(history)
      total_validated = total_validated + 1
      
      if valid then
        Utils.info("✅ " .. history.filename .. " - validation passed")
      else
        Utils.error("❌ " .. history.filename .. " - validation failed")
        for _, error in ipairs(errors) do
          Utils.error("   • " .. error)
        end
        total_errors = total_errors + #errors
      end
      
      if details and details.warnings then
        for _, warning in ipairs(details.warnings) do
          Utils.warn("   ⚠️  " .. warning)
        end
        total_warnings = total_warnings + #details.warnings
      end
    else
      Utils.info("⏭️  " .. history.filename .. " - skipped (not unified format)")
    end
  end
  
  Utils.info("🏁 Validation complete:")
  Utils.info("   Files validated: " .. total_validated)
  Utils.info("   Total errors: " .. total_errors)
  Utils.info("   Total warnings: " .. total_warnings)
end

---Creates a manual migration report
---@param bufnr integer Buffer number
---@return table report Migration report data
function M.create_migration_report(bufnr)
  local histories = Path.history.list(bufnr)
  local report = {
    buffer = bufnr,
    timestamp = Utils.get_timestamp(),
    total_files = #histories,
    unified_files = {},
    legacy_files = {},
    unknown_files = {},
    recommendations = {},
  }
  
  for _, history in ipairs(histories) do
    local file_info = {
      filename = history.filename,
      title = history.title,
      message_count = history.messages and #history.messages or #(history.entries or {}),
      size_estimate = vim.json.encode(history):len(),
    }
    
    if Migration.is_unified_format(history) then
      file_info.version = history.version
      file_info.migration_date = history.migration_metadata and history.migration_metadata.last_migrated
      table.insert(report.unified_files, file_info)
    elseif Migration.is_legacy_format(history) then
      table.insert(report.legacy_files, file_info)
      table.insert(report.recommendations, "Migrate " .. history.filename .. " to unified format")
    else
      table.insert(report.unknown_files, file_info)
      table.insert(report.recommendations, "Investigate " .. history.filename .. " - unknown format")
    end
  end
  
  return report
end

return M
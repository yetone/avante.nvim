local Utils = require("avante.utils")
local Path = require("plenary.path")
local Migration = require("avante.history.migration")

---@class avante.storage.Engine
local Storage = {}

---@class avante.storage.Options
---@field auto_migrate? boolean Automatically migrate legacy formats
---@field backup? boolean Create backup before operations
---@field validate? boolean Validate data integrity
---@field atomic? boolean Use atomic write operations
---@field compress? boolean Compress large data (future feature)

---Validates JSON data structure before writing
---@param data table
---@return boolean success, string? error
local function validate_json_structure(data)
  if type(data) ~= "table" then
    return false, "Data must be a table"
  end
  
  -- Test JSON serialization/deserialization
  local json_success, json_content = pcall(vim.json.encode, data)
  if not json_success then
    return false, "Failed to serialize to JSON: " .. tostring(json_content)
  end
  
  local parse_success, parsed_data = pcall(vim.json.decode, json_content)
  if not parse_success then
    return false, "Failed to parse serialized JSON: " .. tostring(parsed_data)
  end
  
  return true, nil
end

---Performs atomic write operation with rollback capability
---@param filepath Path
---@param data table
---@param backup_path? Path
---@return boolean success, string? error
function Storage.atomic_write(filepath, data, backup_path)
  local temp_path = Path:new(tostring(filepath) .. ".tmp")
  
  -- Validate data structure
  local validate_success, validate_error = validate_json_structure(data)
  if not validate_success then
    return false, "Data validation failed: " .. tostring(validate_error)
  end
  
  local json_content = vim.json.encode(data)
  
  -- Create backup if requested and original file exists
  if backup_path and filepath:exists() then
    local backup_success, backup_error = pcall(function()
      filepath:copy({ destination = backup_path })
    end)
    if not backup_success then
      return false, "Failed to create backup: " .. tostring(backup_error)
    end
  end
  
  -- Write to temporary file first
  local write_success, write_error = pcall(function()
    temp_path:write(json_content, "w")
  end)
  
  if not write_success then
    return false, "Failed to write temporary file: " .. tostring(write_error)
  end
  
  -- Atomic move to final location
  local move_success, move_error = pcall(function()
    temp_path:rename(tostring(filepath))
  end)
  
  if not move_success then
    temp_path:rm() -- Cleanup temporary file
    return false, "Failed to move temporary file: " .. tostring(move_error)
  end
  
  return true, nil
end

---Load with format detection and automatic migration
---@param bufnr integer
---@param filename? string
---@param options? avante.storage.Options
---@return avante.UnifiedChatHistory, boolean is_migrated, string? error
function Storage.load_with_migration(bufnr, filename, options)
  options = options or { auto_migrate = true, backup = true, validate = true }
  local History = require("avante.path").history
  
  local history_filepath = filename and History.get_filepath(bufnr, filename)
    or History.get_latest_filepath(bufnr, false)
    
  if not history_filepath:exists() then
    return History.new(bufnr), false, nil
  end
  
  local content = history_filepath:read()
  if not content or content == "" then
    return History.new(bufnr), false, "File is empty or unreadable"
  end
  
  local parse_success, raw_history = pcall(vim.json.decode, content)
  if not parse_success then
    return History.new(bufnr), false, "Failed to parse JSON: " .. tostring(raw_history)
  end
  
  local format = Migration.detect_format(raw_history)
  
  -- Handle legacy format with automatic migration
  if format == "ChatHistoryEntry" and options.auto_migrate then
    Utils.info("Migrating legacy format: " .. tostring(history_filepath))
    
    -- Create backup if requested
    local backup_path = nil
    if options.backup then
      backup_path = Path:new(tostring(history_filepath) .. ".legacy_backup_" .. os.time())
    end
    
    local unified_history, conversion_warnings = Migration.convert_legacy_format(raw_history)
    
    if #conversion_warnings > 0 then
      Utils.warn("Migration warnings: " .. table.concat(conversion_warnings, ", "))
    end
    
    -- Validate migration if requested
    if options.validate then
      local validation_success, validation_errors = Migration.validate_migration(unified_history, raw_history)
      if not validation_success then
        return History.new(bufnr), false, "Migration validation failed: " .. table.concat(validation_errors, "; ")
      end
    end
    
    -- Save migrated format atomically
    local save_success, save_error = Storage.atomic_write(history_filepath, unified_history, backup_path)
    if not save_success then
      return History.new(bufnr), false, "Failed to save migrated format: " .. tostring(save_error)
    end
    
    -- Ensure filename is set
    local P = require("avante.path")
    unified_history.filename = filename or P.filepath_to_filename(history_filepath)
    return unified_history, true, nil
  end
  
  -- Handle unknown format
  if format == "unknown" then
    return History.new(bufnr), false, "Unknown or invalid history format"
  end
  
  -- Already in unified format or migration not requested
  local P = require("avante.path")
  raw_history.filename = filename or P.filepath_to_filename(history_filepath)
  return raw_history, false, nil
end

---Enhanced save function with options
---@param bufnr integer
---@param history avante.UnifiedChatHistory
---@param options? avante.storage.Options
---@return boolean success, string? error
function Storage.save_with_options(bufnr, history, options)
  options = options or { atomic = true, backup = false, validate = true }
  local History = require("avante.path").history
  
  -- Validate data if requested
  if options.validate then
    local validate_success, validate_error = validate_json_structure(history)
    if not validate_success then
      return false, "History validation failed: " .. tostring(validate_error)
    end
    
    -- Ensure version is set for unified format
    if not history.version then
      history.version = "2.0"
    end
    
    -- Ensure required fields exist
    if not history.messages then
      history.messages = {}
    end
  end
  
  local history_filepath = History.get_filepath(bufnr, history.filename)
  
  local backup_path = nil
  if options.backup and history_filepath:exists() then
    backup_path = Path:new(tostring(history_filepath) .. ".backup_" .. os.time())
  end
  
  local save_success, save_error
  if options.atomic then
    save_success, save_error = Storage.atomic_write(history_filepath, history, backup_path)
  else
    -- Fallback to simple write
    save_success, save_error = pcall(function()
      history_filepath:write(vim.json.encode(history), "w")
    end)
    if not save_success then
      save_error = "Failed to write file: " .. tostring(save_error)
    end
  end
  
  if save_success then
    History.save_latest_filename(bufnr, history.filename)
  end
  
  return save_success, save_error
end

---Batch migration with progress reporting
---@param bufnr integer
---@param progress_callback? fun(current: integer, total: integer, file: string)
---@param options? avante.storage.Options
---@return boolean success, table results
function Storage.batch_migrate(bufnr, progress_callback, options)
  options = options or { backup = true, validate = true }
  return Migration.migrate_project(bufnr, progress_callback)
end

---Validates all history files in a project
---@param bufnr integer
---@return boolean success, table results
function Storage.validate_all_files(bufnr)
  local History = require("avante.path").history
  local history_dir = History.get_history_dir(bufnr)
  local results = {
    total_files = 0,
    valid_files = 0,
    invalid_files = 0,
    errors = {}
  }
  
  if not history_dir:exists() then
    return true, results
  end
  
  local files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
  
  for _, file in ipairs(files) do
    if not file:match("metadata.json") then
      results.total_files = results.total_files + 1
      local filepath = Path:new(file)
      local content = filepath:read()
      
      if content and content ~= "" then
        local parse_success, raw_history = pcall(vim.json.decode, content)
        if parse_success then
          local format = Migration.detect_format(raw_history)
          if format ~= "unknown" then
            results.valid_files = results.valid_files + 1
          else
            results.invalid_files = results.invalid_files + 1
            table.insert(results.errors, {
              file = tostring(filepath),
              error = "Unknown format"
            })
          end
        else
          results.invalid_files = results.invalid_files + 1
          table.insert(results.errors, {
            file = tostring(filepath),
            error = "JSON parse error: " .. tostring(raw_history)
          })
        end
      else
        results.invalid_files = results.invalid_files + 1
        table.insert(results.errors, {
          file = tostring(filepath),
          error = "File is empty or unreadable"
        })
      end
    end
  end
  
  return results.invalid_files == 0, results
end

---Gets performance statistics for storage operations
---@param bufnr integer
---@return table stats
function Storage.get_performance_stats(bufnr)
  local History = require("avante.path").history
  local history_dir = History.get_history_dir(bufnr)
  local stats = {
    total_files = 0,
    total_size_bytes = 0,
    average_file_size = 0,
    largest_file = "",
    largest_file_size = 0
  }
  
  if not history_dir:exists() then
    return stats
  end
  
  local files = vim.fn.glob(tostring(history_dir:joinpath("*.json")), true, true)
  
  for _, file in ipairs(files) do
    if not file:match("metadata.json") then
      local filepath = Path:new(file)
      if filepath:exists() then
        local size = filepath:stat().size or 0
        stats.total_files = stats.total_files + 1
        stats.total_size_bytes = stats.total_size_bytes + size
        
        if size > stats.largest_file_size then
          stats.largest_file_size = size
          stats.largest_file = tostring(filepath)
        end
      end
    end
  end
  
  if stats.total_files > 0 then
    stats.average_file_size = stats.total_size_bytes / stats.total_files
  end
  
  return stats
end

return Storage
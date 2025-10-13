---@class avante.Errors
local M = {}

---@class avante.Error
---@field message string
---@field code number
---@field context? table

---Error codes for different types of failures
M.CODES = {
  MODULE_NOT_FOUND = 1001,
  CONFIGURATION_ERROR = 1002,
  FFI_BINDING_ERROR = 1003,
  VALIDATION_ERROR = 1004,
  TIMEOUT_ERROR = 1005,
  RESOURCE_ERROR = 1006,
  UNKNOWN_ERROR = 9999,
}

---Handle errors gracefully with proper logging and user feedback
---@param err string|table Error message or error object
---@param context? table Additional context information
---@return nil
function M.handle_error(err, context)
  local error_msg = type(err) == "string" and err or (err.message or tostring(err))
  local error_code = type(err) == "table" and err.code or M.CODES.UNKNOWN_ERROR

  -- Log the error with context
  local log_msg = string.format("[Avante Error %d]: %s", error_code, error_msg)
  if context then
    log_msg = log_msg .. " | Context: " .. vim.inspect(context)
  end

  -- Use vim.notify for user-friendly error display
  vim.notify("Avante error: " .. error_msg, vim.log.levels.ERROR)

  -- Log detailed information for debugging
  if vim.g.avante_debug then
    vim.notify(log_msg, vim.log.levels.DEBUG)
  end

  return nil
end

---Validate input parameters
---@param input any Input to validate
---@param expected_type string Expected type (e.g., "string", "table", "number")
---@param field_name? string Name of the field being validated (for better error messages)
---@return boolean is_valid True if input is valid
---@return string? error_msg Error message if validation fails
function M.validate_input(input, expected_type, field_name)
  local actual_type = type(input)
  local field_desc = field_name and (" for field '" .. field_name .. "'") or ""

  if actual_type ~= expected_type then
    local error_msg = string.format(
      "Invalid input type%s: expected '%s', got '%s'",
      field_desc, expected_type, actual_type
    )
    return false, error_msg
  end

  return true, nil
end

---Validate configuration object
---@param config table Configuration to validate
---@param schema table Schema definition with required fields and types
---@return boolean is_valid True if configuration is valid
---@return string? error_msg Error message if validation fails
function M.validate_config(config, schema)
  if not M.validate_input(config, "table", "config") then
    return false, "Configuration must be a table"
  end

  for field, field_schema in pairs(schema) do
    local value = config[field]
    local required = field_schema.required or false
    local expected_type = field_schema.type

    if required and value == nil then
      return false, string.format("Required field '%s' is missing", field)
    end

    if value ~= nil then
      local is_valid, error_msg = M.validate_input(value, expected_type, field)
      if not is_valid then
        return false, error_msg
      end
    end
  end

  return true, nil
end

---Create a standardized error object
---@param message string Error message
---@param code? number Error code (defaults to UNKNOWN_ERROR)
---@param context? table Additional context
---@return avante.Error
function M.create_error(message, code, context)
  return {
    message = message,
    code = code or M.CODES.UNKNOWN_ERROR,
    context = context,
  }
end

---Safely execute a function with error handling
---@param func function Function to execute
---@param error_context? string Context description for error reporting
---@return any result Function result on success, nil on error
---@return string? error Error message if function failed
function M.safe_execute(func, error_context)
  local ok, result = pcall(func)

  if not ok then
    local context_msg = error_context and (" in " .. error_context) or ""
    local error_msg = "Execution failed" .. context_msg .. ": " .. tostring(result)
    M.handle_error(error_msg)
    return nil, error_msg
  end

  return result, nil
end

---Check if a module can be loaded without actually loading it
---@param module_name string Module name to check
---@return boolean can_load True if module can be loaded
function M.can_load_module(module_name)
  local ok, _ = pcall(require, module_name)
  return ok
end

---Require a module with error handling
---@param module_name string Module name to require
---@param optional? boolean If true, don't show error for missing optional modules
---@return table? module Loaded module on success, nil on error
---@return string? error Error message if loading failed
function M.safe_require(module_name, optional)
  local ok, module = pcall(require, module_name)

  if not ok then
    local error_msg = string.format("Failed to load module '%s': %s", module_name, tostring(module))
    if not optional then
      M.handle_error(M.create_error(error_msg, M.CODES.MODULE_NOT_FOUND, { module = module_name }))
    end
    return nil, error_msg
  end

  return module, nil
end

return M
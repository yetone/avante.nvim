---@class avante.test.Config
local M = {}

local Utils = require("avante.utils")
local Errors = require("avante.errors")

---Default test configuration following Avante.nvim patterns
M.defaults = {
  __inherited_from = "base_test",
  timeout = 30000,
  parallel_execution = false,
  output_format = "detailed",
  error_handling = "continue",
  performance_tracking = true,
  graceful_degradation = true,
  fallback_indicators = {
    timeout = 999.0,
    memory_limit = 999999
  },
  suites = {
    basic_functionality = { enabled = true },
    error_handling = { enabled = true },
    configuration = { enabled = true },
    integration = { enabled = true },
    performance = { enabled = true }
  },
  environment = {
    isolated = true,
    cleanup_after_tests = true,
    preserve_state = false
  },
  reporting = {
    verbose = false,
    include_stack_traces = true,
    performance_metrics = true
  }
}

---Validate test configuration following error handling patterns
---@param config table
---@return boolean, string?
function M.validate(config)
  local schema = {
    timeout = { type = "number", required = false },
    parallel_execution = { type = "boolean", required = false },
    output_format = { type = "string", required = false },
    error_handling = { type = "string", required = false },
    performance_tracking = { type = "boolean", required = false },
    graceful_degradation = { type = "boolean", required = false }
  }

  return Errors.validate_config(config, schema)
end

---Merge user configuration with defaults using deep extend
---@param user_config? table
---@return table
function M.merge(user_config)
  if not user_config then
    return vim.deepcopy(M.defaults)
  end

  -- Validate configuration first
  local is_valid, error_msg = M.validate(user_config)
  if not is_valid then
    Utils.warn("Invalid test configuration: " .. (error_msg or "unknown error"))
    return vim.deepcopy(M.defaults)
  end

  -- Deep merge following Avante.nvim configuration patterns
  return vim.tbl_deep_extend("force", M.defaults, user_config)
end

---Configuration validation for environment variables following E.parse_envvar pattern
---@param config table
---@return table
function M.apply_environment_overrides(config)
  -- Check for environment variable overrides
  local env_timeout = os.getenv("AVANTE_TEST_TIMEOUT")
  if env_timeout then
    local timeout_num = tonumber(env_timeout)
    if timeout_num then
      config.timeout = timeout_num
      Utils.debug("Applied timeout override from environment: " .. timeout_num)
    end
  end

  local env_debug = os.getenv("AVANTE_TEST_DEBUG")
  if env_debug then
    local debug_bool = env_debug:lower() == "true" or env_debug == "1"
    config.reporting.verbose = debug_bool
    Utils.debug("Applied debug override from environment: " .. tostring(debug_bool))
  end

  return config
end

---Get suite configuration with inheritance support
---@param suite_name string
---@param config table
---@return table
function M.get_suite_config(suite_name, config)
  local base_suite_config = {
    enabled = true,
    timeout = config.timeout,
    retry_count = 0,
    setup_timeout = 5000,
    teardown_timeout = 5000
  }

  local suite_config = config.suites and config.suites[suite_name] or {}

  return vim.tbl_deep_extend("force", base_suite_config, suite_config)
end

---Configuration for performance benchmarking
---@param config table
---@return table
function M.get_performance_config(config)
  return {
    startup_target_ms = 100,
    memory_target_kb = 51200, -- 50MB
    operation_target_ms = 5000, -- 5 seconds
    enable_profiling = config.performance_tracking,
    fallback_values = config.fallback_indicators
  }
end

return M
---@class avante.test.Validator
local M = {}

local Utils = require("avante.utils")
local Errors = require("avante.errors")

---Validate test suite exists and is properly structured
---@param suite_name string
---@return boolean, string?
function M.validate_suite(suite_name)
  -- Check if suite module exists
  local suite_ok, suite_module = pcall(require, "tests." .. suite_name .. "_spec")
  if not suite_ok then
    return false, "Suite module not found: " .. suite_name
  end

  -- Basic validation that it's a proper test module
  if type(suite_module) ~= "table" then
    return false, "Suite module should export a table: " .. suite_name
  end

  return true, nil
end

---Validate test environment setup
---@return boolean, string?
function M.validate_environment()
  -- Check required modules are available
  local required_modules = {
    "avante",
    "avante.config",
    "avante.errors",
    "avante.utils"
  }

  for _, module_name in ipairs(required_modules) do
    local module, error_msg = Errors.safe_require(module_name)
    if not module then
      return false, "Required module missing: " .. module_name .. " - " .. (error_msg or "unknown error")
    end
  end

  -- Check Neovim version compatibility
  if vim.fn.has("nvim-0.9") == 0 then
    return false, "Neovim 0.9+ required for test framework"
  end

  return true, nil
end

---Validate performance benchmarking setup
---@return boolean, string?
function M.validate_benchmark_environment()
  local benchmark_ok, benchmark = Errors.safe_require("tests.performance.benchmark", true)
  if not benchmark_ok then
    return false, "Benchmark module not available"
  end

  -- Check essential benchmark functions
  local required_functions = {
    "measure_startup_time",
    "profile_memory_usage",
    "run_comprehensive_benchmarks"
  }

  for _, func_name in ipairs(required_functions) do
    if type(benchmark[func_name]) ~= "function" then
      return false, "Benchmark function missing: " .. func_name
    end
  end

  return true, nil
end

---Validate test configuration
---@param config table
---@return boolean, string?
function M.validate_test_config(config)
  local test_config_module = require("avante.test.config")
  return test_config_module.validate(config)
end

---Validate entire test framework setup
---@return boolean, string[]
function M.validate_framework()
  local errors = {}

  local env_ok, env_err = M.validate_environment()
  if not env_ok then
    table.insert(errors, "Environment: " .. env_err)
  end

  local benchmark_ok, benchmark_err = M.validate_benchmark_environment()
  if not benchmark_ok then
    table.insert(errors, "Benchmark: " .. benchmark_err)
  end

  -- Validate core test suites
  local core_suites = {
    "basic_functionality",
    "error_handling",
    "configuration",
    "integration",
    "performance"
  }

  for _, suite_name in ipairs(core_suites) do
    local suite_ok, suite_err = M.validate_suite(suite_name)
    if not suite_ok then
      table.insert(errors, "Suite " .. suite_name .. ": " .. suite_err)
    end
  end

  local all_valid = #errors == 0
  return all_valid, errors
end

return M
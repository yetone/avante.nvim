---@class avante.test.Runner
local M = {}

local Utils = require("avante.utils")
local Errors = require("avante.errors")

---@class avante.TestSuite
---@field name string
---@field tests function[]
---@field setup? function
---@field teardown? function

---@class avante.TestExecutionConfig
---@field timeout number
---@field parallel_execution boolean
---@field output_format string
---@field error_handling string
---@field performance_tracking boolean
---@field graceful_degradation boolean
---@field fallback_indicators table

local default_config = {
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
  }
}

---Run test suites following provider inheritance pattern
---@param config avante.TestExecutionConfig
---@return avante.TestResult[]
function M.run_tests(config)
  config = vim.tbl_deep_extend("force", default_config, config or {})

  local results = {}
  local test_suites = {
    "basic_functionality",
    "error_handling",
    "configuration",
    "integration",
    "performance"
  }

  Utils.debug("Starting test execution with config", config)

  for _, suite_name in ipairs(test_suites) do
    local suite_results = M.run_test_suite(suite_name, config)
    for _, result in ipairs(suite_results) do
      table.insert(results, result)
    end

    -- Handle error strategy
    if config.error_handling == "stop" and not M.all_passed(suite_results) then
      Utils.warn("Stopping test execution due to failures in suite: " .. suite_name)
      break
    end
  end

  return results
end

---Run individual test suite
---@param suite_name string
---@param config avante.TestExecutionConfig
---@return avante.TestResult[]
function M.run_test_suite(suite_name, config)
  local results = {}

  local suite_ok, suite_module = pcall(require, "tests." .. suite_name .. "_spec")
  if not suite_ok then
    local fallback_result = {
      success = false,
      message = "Failed to load test suite: " .. suite_name,
      duration_ms = config.fallback_indicators.timeout,
      error = "Suite module not found: " .. tostring(suite_module)
    }
    return { fallback_result }
  end

  Utils.debug("Running test suite: " .. suite_name)

  -- Use executor to run the suite
  local executor = require("avante.test.executor")
  local suite_results = executor.execute_suite(suite_name, config)

  return suite_results
end

---Check if all tests in results passed
---@param results avante.TestResult[]
---@return boolean
function M.all_passed(results)
  for _, result in ipairs(results) do
    if not result.success then
      return false
    end
  end
  return true
end

---Get test metrics for performance tracking
---@param results avante.TestResult[]
---@return table
function M.get_metrics(results)
  local total_tests = #results
  local passed_tests = 0
  local total_duration = 0

  for _, result in ipairs(results) do
    if result.success then
      passed_tests = passed_tests + 1
    end
    total_duration = total_duration + (result.duration_ms or 0)
  end

  return {
    total_tests = total_tests,
    passed_tests = passed_tests,
    failed_tests = total_tests - passed_tests,
    success_rate = total_tests > 0 and (passed_tests / total_tests) or 0,
    total_duration_ms = total_duration,
    average_duration_ms = total_tests > 0 and (total_duration / total_tests) or 0
  }
end

return M
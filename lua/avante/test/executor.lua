---@class avante.test.Executor
local M = {}

local Utils = require("avante.utils")
local Errors = require("avante.errors")

---Execute individual test suite with timeout handling
---@param suite_name string
---@param config avante.TestExecutionConfig
---@return avante.TestResult[]
function M.execute_suite(suite_name, config)
  local results = {}

  -- Use safe_execute for consistent error handling
  local start_time = vim.uv.hrtime()
  local suite_result, error_msg = Errors.safe_execute(function()
    return M.run_suite_tests(suite_name, config)
  end, "test suite execution")

  local end_time = vim.uv.hrtime()
  local duration_ms = (end_time - start_time) / 1000000

  if suite_result then
    results = suite_result
  else
    -- Graceful degradation following technical design
    local fallback_result = {
      success = false,
      message = "Suite execution failed: " .. suite_name,
      duration_ms = config.fallback_indicators.timeout,
      error = error_msg or "Unknown execution error"
    }
    results = { fallback_result }
  end

  -- Add performance metadata to results
  if config.performance_tracking then
    for _, result in ipairs(results) do
      result.suite_name = suite_name
      result.execution_time_ms = duration_ms
    end
  end

  return results
end

---Run tests within a suite with proper resource cleanup
---@param suite_name string
---@param config avante.TestExecutionConfig
---@return avante.TestResult[]
function M.run_suite_tests(suite_name, config)
  local results = {}

  -- Mock test execution based on available test specs
  local test_functions = M.get_suite_test_functions(suite_name)

  for i, test_func in ipairs(test_functions) do
    local test_name = suite_name .. "_test_" .. i
    local test_result = M.execute_single_test(test_name, test_func, config)
    table.insert(results, test_result)

    -- Handle timeout per test
    if test_result.duration_ms and test_result.duration_ms > config.timeout then
      Utils.warn("Test timeout exceeded: " .. test_name)
      test_result.success = false
      test_result.error = "Test timeout exceeded"
    end
  end

  return results
end

---Execute single test with error handling and resource management
---@param test_name string
---@param test_func function
---@param config avante.TestExecutionConfig
---@return avante.TestResult
function M.execute_single_test(test_name, test_func, config)
  local start_time = vim.uv.hrtime()

  -- Test isolation - each test runs independently
  local test_result, error_msg = Errors.safe_execute(test_func, test_name)

  local end_time = vim.uv.hrtime()
  local duration_ms = (end_time - start_time) / 1000000

  local result = {
    success = test_result ~= nil,
    message = test_name,
    duration_ms = duration_ms,
    error = error_msg
  }

  if config.graceful_degradation and not result.success then
    -- Apply fallback mechanisms
    result.duration_ms = config.fallback_indicators.timeout
    Utils.debug("Applied graceful degradation for test: " .. test_name)
  end

  return result
end

---Get test functions for a suite (mock implementation)
---@param suite_name string
---@return function[]
function M.get_suite_test_functions(suite_name)
  -- Mock test functions that verify module existence and basic functionality
  local basic_tests = {}

  if suite_name == "basic_functionality" then
    table.insert(basic_tests, function()
      local avante = require("avante")
      assert(avante, "Avante module should load")
      assert(type(avante.setup) == "function", "Setup function should exist")
      avante.setup({})
      return true
    end)

    table.insert(basic_tests, function()
      local config = require("avante.config")
      assert(config._defaults, "Default configuration should exist")
      return true
    end)
  elseif suite_name == "error_handling" then
    table.insert(basic_tests, function()
      local errors = require("avante.errors")
      assert(type(errors.handle_error) == "function", "Error handler should exist")
      errors.handle_error("Test error", { test = true })
      return true
    end)
  elseif suite_name == "configuration" then
    table.insert(basic_tests, function()
      local config = require("avante.config")
      local valid_config = { provider = "test", debug = false }
      local schema = { provider = { type = "string", required = true } }
      local errors = require("avante.errors")
      local is_valid = errors.validate_config(valid_config, schema)
      assert(is_valid, "Configuration validation should work")
      return true
    end)
  elseif suite_name == "integration" then
    table.insert(basic_tests, function()
      -- Test integration between modules
      local avante = require("avante")
      local config = require("avante.config")
      local errors = require("avante.errors")
      avante.setup({})
      return true
    end)
  elseif suite_name == "performance" then
    table.insert(basic_tests, function()
      local benchmark = require("tests.performance.benchmark")
      local startup_time = benchmark.measure_startup_time()
      assert(type(startup_time) == "number", "Startup time should be measured")
      return true
    end)
  end

  return basic_tests
end

return M
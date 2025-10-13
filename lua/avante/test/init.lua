---@class avante.test
local M = {}

local Utils = require("avante.utils")
local Errors = require("avante.errors")

---@class avante.TestResult
---@field success boolean
---@field message string
---@field duration_ms number
---@field error? string

---@class avante.TestConfig
---@field timeout? number Default: 30000ms
---@field parallel_execution? boolean Default: false
---@field output_format? "detailed" | "summary" Default: "detailed"
---@field error_handling? "continue" | "stop" Default: "continue"
---@field performance_tracking? boolean Default: true

---Main test interface following Avante.nvim patterns
---@param config? avante.TestConfig
---@return avante.TestResult[]
function M.execute(config)
  config = config or {}

  local runner = require("avante.test.runner")
  return runner.run_tests(config)
end

---Generate comprehensive report
---@param results avante.TestResult[]
---@param options? table
---@return string
function M.report(results, options)
  options = options or {}

  local reporter = require("avante.test.reporter")
  return reporter.generate_report(results, options)
end

---Validate test suite
---@param suite_name string
---@return boolean, string?
function M.validate(suite_name)
  local validator = require("avante.test.validator")
  return validator.validate_suite(suite_name)
end

---Run benchmark tests
---@param suite_name string
---@return table
function M.benchmark(suite_name)
  local benchmark = require("tests.performance.benchmark")

  if suite_name == "comprehensive" then
    return benchmark.run_comprehensive_benchmarks()
  else
    Utils.warn("Unknown benchmark suite: " .. suite_name)
    return {}
  end
end

return M
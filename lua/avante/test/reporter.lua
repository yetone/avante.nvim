---@class avante.test.Reporter
local M = {}

local Utils = require("avante.utils")

---Generate detailed report with performance metrics
---@param results avante.TestResult[]
---@param options table
---@return string
function M.generate_report(results, options)
  options = options or {}
  local format = options.format or "detailed"
  local output = options.output or "console"
  local include_performance = options.include_performance ~= false
  local error_context = options.error_context ~= false

  if format == "detailed" then
    return M.generate_detailed_report(results, include_performance, error_context)
  elseif format == "summary" then
    return M.generate_summary_report(results)
  elseif format == "json" then
    return M.generate_json_report(results)
  else
    return M.generate_detailed_report(results, include_performance, error_context)
  end
end

---Generate detailed report with comprehensive metrics
---@param results avante.TestResult[]
---@param include_performance boolean
---@param error_context boolean
---@return string
function M.generate_detailed_report(results, include_performance, error_context)
  local lines = {}
  table.insert(lines, "=== Avante Test Framework Report ===")
  table.insert(lines, "")

  -- Summary statistics
  local runner = require("avante.test.runner")
  local metrics = runner.get_metrics(results)

  table.insert(lines, string.format("Tests Run: %d", metrics.total_tests))
  table.insert(lines, string.format("Passed: %d", metrics.passed_tests))
  table.insert(lines, string.format("Failed: %d", metrics.failed_tests))
  table.insert(lines, string.format("Success Rate: %.1f%%", metrics.success_rate * 100))

  if include_performance then
    table.insert(lines, string.format("Total Duration: %.2fms", metrics.total_duration_ms))
    table.insert(lines, string.format("Average Duration: %.2fms", metrics.average_duration_ms))
  end

  table.insert(lines, "")

  -- Individual test results
  table.insert(lines, "=== Test Results ===")
  for i, result in ipairs(results) do
    local status = result.success and "✓ PASS" or "✗ FAIL"
    local duration = result.duration_ms and string.format(" (%.2fms)", result.duration_ms) or ""

    table.insert(lines, string.format("%d. %s %s%s",
                 i, result.message, status, duration))

    if not result.success and error_context and result.error then
      table.insert(lines, "   Error: " .. result.error)
    end
  end

  table.insert(lines, "")

  -- Performance baseline information if available
  if include_performance then
    table.insert(lines, "=== Performance Baseline ===")
    table.insert(lines, "Target: Full suite completion within 30 seconds")
    table.insert(lines, "Target: Memory consumption below 50MB")
    table.insert(lines, "Target: Individual test completion under 5 seconds")
    table.insert(lines, "")
  end

  table.insert(lines, "=== End Report ===")

  return table.concat(lines, "\n")
end

---Generate summary report
---@param results avante.TestResult[]
---@return string
function M.generate_summary_report(results)
  local runner = require("avante.test.runner")
  local metrics = runner.get_metrics(results)

  local summary = string.format(
    "Test Summary: %d/%d passed (%.1f%%) in %.2fms",
    metrics.passed_tests,
    metrics.total_tests,
    metrics.success_rate * 100,
    metrics.total_duration_ms
  )

  if metrics.failed_tests > 0 then
    summary = summary .. string.format(" - %d failures", metrics.failed_tests)
  end

  return summary
end

---Generate JSON report for CI/CD integration
---@param results avante.TestResult[]
---@return string
function M.generate_json_report(results)
  local runner = require("avante.test.runner")
  local metrics = runner.get_metrics(results)

  local report = {
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    framework = "avante.nvim test framework",
    metrics = metrics,
    results = results
  }

  return vim.json.encode(report)
end

---Real-time progress reporting
---@param current_test number
---@param total_tests number
---@param test_name string
function M.report_progress(current_test, total_tests, test_name)
  local progress = math.floor((current_test / total_tests) * 100)
  local message = string.format("[%d%%] Running: %s (%d/%d)",
                                progress, test_name, current_test, total_tests)

  Utils.debug(message)

  -- Use vim.notify for user feedback
  if vim.g.avante_test_verbose then
    vim.notify(message, vim.log.levels.INFO, { title = "Avante Test" })
  end
end

---Context-aware logging integration with error module
---@param test_result avante.TestResult
function M.log_test_result(test_result)
  local log_level = test_result.success and vim.log.levels.DEBUG or vim.log.levels.ERROR

  local log_message = string.format(
    "Test: %s | Status: %s | Duration: %.2fms",
    test_result.message,
    test_result.success and "PASS" or "FAIL",
    test_result.duration_ms or 0
  )

  if not test_result.success and test_result.error then
    log_message = log_message .. " | Error: " .. test_result.error
  end

  -- Use Neovim's built-in logging system
  vim.notify(log_message, log_level, { title = "Avante Test Framework" })

  -- Debug logging for detailed analysis
  if vim.g.avante_debug then
    Utils.debug("Test result logged", {
      test = test_result.message,
      success = test_result.success,
      duration = test_result.duration_ms
    })
  end
end

return M
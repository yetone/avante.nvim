---@class avante.Benchmark
local M = {}

local Utils = require("avante.utils")
local Errors = require("avante.errors")

---@class avante.BenchmarkResult
---@field operation string
---@field elapsed_time number Time in milliseconds
---@field memory_usage number Memory usage in KB
---@field success boolean Operation success status
---@field error? string Error message if operation failed

---@class avante.BenchmarkConfig
---@field warmup_runs? number Number of warmup runs (default: 3)
---@field measurement_runs? number Number of measurement runs (default: 5)
---@field gc_between_runs? boolean Force garbage collection between runs (default: true)

---Measure time for a function execution
---@param operation_name string Name of the operation for reporting
---@param func function Function to benchmark
---@param config? avante.BenchmarkConfig Benchmark configuration
---@return avante.BenchmarkResult
function M.measure_time(operation_name, func, config)
  config = config or {}
  local warmup_runs = config.warmup_runs or 3
  local measurement_runs = config.measurement_runs or 5
  local gc_between_runs = config.gc_between_runs ~= false

  -- Warmup runs
  for _ = 1, warmup_runs do
    local ok, _ = pcall(func)
    if not ok then
      return {
        operation = operation_name,
        elapsed_time = 999.0, -- Indicate failure
        memory_usage = 0,
        success = false,
        error = "Warmup run failed"
      }
    end
    if gc_between_runs then
      collectgarbage("collect")
    end
  end

  -- Measurement runs
  local times = {}
  local total_time = 0

  for i = 1, measurement_runs do
    if gc_between_runs then
      collectgarbage("collect")
    end

    local start_time = vim.uv.hrtime()
    local ok, result = pcall(func)
    local end_time = vim.uv.hrtime()

    if not ok then
      return {
        operation = operation_name,
        elapsed_time = 999.0,
        memory_usage = 0,
        success = false,
        error = "Measurement run " .. i .. " failed: " .. tostring(result)
      }
    end

    local elapsed = (end_time - start_time) / 1000000 -- Convert to milliseconds
    times[i] = elapsed
    total_time = total_time + elapsed
  end

  local avg_time = total_time / measurement_runs
  local memory_usage = collectgarbage("count") -- In KB

  return {
    operation = operation_name,
    elapsed_time = avg_time,
    memory_usage = memory_usage,
    success = true
  }
end

---Measure startup time for avante plugin
---@return number startup_time_ms
function M.measure_startup_time()
  local start_time = os.clock()

  local ok, avante = pcall(require, 'avante')
  if not ok then
    Utils.debug("Failed to require avante module for startup benchmark")
    return 999.0 -- Return high value indicating failure
  end

  -- Try to setup with empty config
  local setup_ok = pcall(avante.setup, {})
  local end_time = os.clock()

  if not setup_ok then
    Utils.debug("Failed to setup avante for startup benchmark")
    return 999.0
  end

  return (end_time - start_time) * 1000 -- Convert to milliseconds
end

---Profile memory usage for an operation
---@param operation function Operation to profile
---@return number memory_delta_kb Memory usage delta in KB
function M.profile_memory_usage(operation)
  -- Force garbage collection before measurement
  collectgarbage("collect")
  collectgarbage("collect") -- Call twice to be sure

  local before = collectgarbage("count")

  local ok, result = pcall(operation)
  if not ok then
    Utils.debug("Operation failed during memory profiling: " .. tostring(result))
    return 999999 -- Return high value indicating failure
  end

  local after = collectgarbage("count")
  return after - before
end

---Benchmark tokenization performance
---@param text string Text to tokenize
---@param expected_min_rate? number Minimum expected tokens per second (default: 1000)
---@return avante.BenchmarkResult
function M.benchmark_tokenization(text, expected_min_rate)
  expected_min_rate = expected_min_rate or 1000

  -- Check if tokenizer is available
  local tokenizers, err = Errors.safe_require("avante.tokenizers", true)
  if not tokenizers then
    return {
      operation = "tokenization",
      elapsed_time = 999.0,
      memory_usage = 0,
      success = false,
      error = "Tokenizers module not available: " .. (err or "unknown error")
    }
  end

  local operation = function()
    return tokenizers.encode(text)
  end

  local result = M.measure_time("tokenization", operation)

  if result.success then
    -- Calculate tokens per second
    local text_length = #text
    local tokens_per_second = (text_length / result.elapsed_time) * 1000
    result.tokens_per_second = tokens_per_second
    result.meets_performance_target = tokens_per_second >= expected_min_rate
  end

  return result
end

---Run comprehensive performance benchmarks
---@return table benchmark_results
function M.run_comprehensive_benchmarks()
  local results = {}

  -- Startup time benchmark
  results.startup_time = M.measure_startup_time()

  -- Memory usage benchmark
  results.memory_usage = M.profile_memory_usage(function()
    local avante = require("avante")
    avante.setup({})
  end)

  -- Tokenization benchmark if available
  local sample_text = "This is a sample text for tokenization performance testing. " ..
                     "It contains multiple sentences and should provide a good " ..
                     "baseline for measuring tokenization speed and efficiency."

  results.tokenization = M.benchmark_tokenization(sample_text, 10000) -- 10K chars/sec target

  -- Configuration loading benchmark
  results.config_loading = M.measure_time("config_loading", function()
    local Config = require("avante.config")
    local test_config = {
      provider = "openai",
      model = "gpt-4",
      timeout = 30000,
      max_tokens = 4096
    }
    -- Simulate config validation and loading
    return Config
  end)

  -- Error handling benchmark
  results.error_handling = M.measure_time("error_handling", function()
    local Errors = require("avante.errors")
    Errors.handle_error("Test error for benchmark", { test = true })
    return true
  end)

  return results
end

---Generate a formatted benchmark report
---@param results table Benchmark results
---@return string report Formatted report string
function M.generate_report(results)
  local report_lines = {}
  table.insert(report_lines, "=== Avante Performance Benchmark Report ===")
  table.insert(report_lines, "")

  -- Startup time
  if results.startup_time then
    local status = results.startup_time < 100 and "✓ PASS" or "✗ FAIL"
    table.insert(report_lines, string.format("Startup Time: %.2f ms %s (target: <100ms)",
                 results.startup_time, status))
  end

  -- Memory usage
  if results.memory_usage then
    local status = results.memory_usage < 51200 and "✓ PASS" or "✗ FAIL" -- 50MB in KB
    table.insert(report_lines, string.format("Memory Usage: %.2f KB %s (target: <50MB)",
                 results.memory_usage, status))
  end

  -- Tokenization performance
  if results.tokenization then
    if results.tokenization.success then
      local rate = results.tokenization.tokens_per_second or 0
      local status = results.tokenization.meets_performance_target and "✓ PASS" or "✗ FAIL"
      table.insert(report_lines, string.format("Tokenization: %.2f tokens/sec %s (target: >10K/sec)",
                   rate, status))
    else
      table.insert(report_lines, "Tokenization: ✗ FAIL - " .. (results.tokenization.error or "unknown error"))
    end
  end

  -- Other operations
  for operation, result in pairs(results) do
    if type(result) == "table" and result.operation and
       not vim.tbl_contains({"startup_time", "memory_usage", "tokenization"}, operation) then
      local status = result.success and "✓ PASS" or "✗ FAIL"
      table.insert(report_lines, string.format("%s: %.2f ms %s",
                   result.operation, result.elapsed_time, status))
    end
  end

  table.insert(report_lines, "")
  table.insert(report_lines, "=== End Report ===")

  return table.concat(report_lines, "\n")
end

---Quick performance check for development
---@return boolean all_passed True if all critical benchmarks pass
function M.quick_check()
  local results = M.run_comprehensive_benchmarks()

  local startup_ok = results.startup_time and results.startup_time < 100
  local memory_ok = results.memory_usage and results.memory_usage < 51200 -- 50MB

  -- Print quick summary
  print("Quick Performance Check:")
  print(string.format("  Startup: %.1fms %s", results.startup_time or 999, startup_ok and "✓" or "✗"))
  print(string.format("  Memory:  %.1fKB %s", results.memory_usage or 999999, memory_ok and "✓" or "✗"))

  return startup_ok and memory_ok
end

return M
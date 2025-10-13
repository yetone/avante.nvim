-- Performance Tests
-- TDD Red Phase - Tests should fail until performance optimizations are implemented

describe("Performance Tests", function()
  local benchmark

  before_each(function()
    -- Reset any cached modules
    package.loaded['tests.performance.benchmark'] = nil
    package.loaded['avante'] = nil
  end)

  describe("Benchmark Module", function()
    it("should load benchmark utilities", function()
      local success, result = pcall(require, 'tests.performance.benchmark')
      assert.is_true(success, "Failed to load benchmark module: " .. tostring(result))
      assert.is_not_nil(result, "Benchmark module returned nil")
      assert.is_table(result, "Benchmark module should return a table")
    end)

    it("should have startup time measurement function", function()
      benchmark = require('tests.performance.benchmark')
      assert.is_function(benchmark.measure_startup_time, "Should have measure_startup_time function")
    end)

    it("should have memory profiling function", function()
      benchmark = require('tests.performance.benchmark')
      assert.is_function(benchmark.profile_memory_usage, "Should have profile_memory_usage function")
    end)
  end)

  describe("Startup Performance", function()
    before_each(function()
      benchmark = require('tests.performance.benchmark')
    end)

    it("should measure plugin startup time", function()
      local startup_time = benchmark.measure_startup_time()
      assert.is_number(startup_time, "Should return numeric startup time")
      assert.is_true(startup_time >= 0, "Startup time should be non-negative")
    end)

    it("should have acceptable startup time", function()
      local startup_time = benchmark.measure_startup_time()
      -- Target: less than 100ms for basic setup
      assert.is_true(startup_time < 0.1, "Startup time should be under 100ms, got: " .. startup_time .. "s")
    end)

    it("should have consistent startup times", function()
      local times = {}
      local iterations = 5

      for i = 1, iterations do
        times[i] = benchmark.measure_startup_time()
      end

      -- Calculate variance
      local sum = 0
      for _, time in ipairs(times) do
        sum = sum + time
      end
      local average = sum / iterations

      local variance_sum = 0
      for _, time in ipairs(times) do
        variance_sum = variance_sum + (time - average) ^ 2
      end
      local variance = variance_sum / iterations

      -- Variance should be low (consistent performance)
      assert.is_true(variance < 0.001, "Startup time should be consistent, variance: " .. variance)
    end)
  end)

  describe("Memory Usage", function()
    before_each(function()
      benchmark = require('tests.performance.benchmark')
    end)

    it("should profile memory usage of operations", function()
      local memory_used = benchmark.profile_memory_usage(function()
        local avante = require('avante')
        avante.setup({})
      end)

      assert.is_number(memory_used, "Should return numeric memory usage")
    end)

    it("should have reasonable memory usage for setup", function()
      local memory_used = benchmark.profile_memory_usage(function()
        local avante = require('avante')
        avante.setup({})
      end)

      -- Should use less than 1MB for basic setup
      assert.is_true(memory_used < 1024, "Memory usage should be reasonable: " .. memory_used .. "KB")
    end)

    it("should not have significant memory leaks", function()
      local baseline_memory = benchmark.profile_memory_usage(function()
        -- Baseline operation
      end)

      local operation_memory = benchmark.profile_memory_usage(function()
        local avante = require('avante')
        for i = 1, 10 do
          avante.setup({})
        end
      end)

      local net_memory = operation_memory - baseline_memory
      -- Should not accumulate too much memory over repeated operations
      assert.is_true(net_memory < 500, "Should not leak significant memory: " .. net_memory .. "KB")
    end)
  end)

  describe("Operation Performance", function()
    before_each(function()
      benchmark = require('tests.performance.benchmark')
    end)

    it("should measure configuration processing speed", function()
      local config_time = benchmark.profile_memory_usage(function()
        local config = require('avante.config')
        for i = 1, 100 do
          config.setup({ provider = 'test' .. i })
        end
      end)

      -- Should process configs quickly
      -- This is more of a memory test but gives us performance insight
      assert.is_true(config_time < 100, "Config processing should be efficient")
    end)

    it("should handle rapid successive operations", function()
      local start_time = os.clock()

      local avante = require('avante')
      for i = 1, 50 do
        avante.setup({ provider = 'rapid_test' .. i })
      end

      local elapsed = os.clock() - start_time
      -- Should handle rapid operations efficiently
      assert.is_true(elapsed < 1.0, "Rapid operations should be fast: " .. elapsed .. "s")
    end)
  end)

  describe("Resource Cleanup", function()
    before_each(function()
      benchmark = require('tests.performance.benchmark')
    end)

    it("should clean up resources properly", function()
      local initial_memory = collectgarbage("count")

      -- Perform operations that should clean up
      local avante = require('avante')
      for i = 1, 20 do
        avante.setup({})
      end

      -- Force cleanup
      collectgarbage("collect")
      local final_memory = collectgarbage("count")

      local memory_diff = final_memory - initial_memory
      -- Should not retain excessive memory after cleanup
      assert.is_true(memory_diff < 200, "Should clean up resources: " .. memory_diff .. "KB retained")
    end)
  end)

  describe("Performance Regression", function()
    it("should maintain performance over time", function()
      -- This test helps catch performance regressions
      local performance_baseline = {
        startup_time = 0.1,  -- 100ms
        memory_usage = 1024, -- 1MB
      }

      benchmark = require('tests.performance.benchmark')

      local current_startup = benchmark.measure_startup_time()
      local current_memory = benchmark.profile_memory_usage(function()
        local avante = require('avante')
        avante.setup({})
      end)

      -- Should not exceed baseline by more than 50%
      assert.is_true(current_startup < performance_baseline.startup_time * 1.5,
        "Startup time regression: " .. current_startup .. "s vs baseline " .. performance_baseline.startup_time .. "s")

      assert.is_true(current_memory < performance_baseline.memory_usage * 1.5,
        "Memory usage regression: " .. current_memory .. "KB vs baseline " .. performance_baseline.memory_usage .. "KB")
    end)
  end)
end)
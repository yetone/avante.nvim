-- Performance benchmarking utilities
-- TDD Red Phase - Basic implementation to support tests

local M = {}

function M.measure_startup_time()
  local start_time = os.clock()

  -- Simulate plugin startup - this will fail until real implementation exists
  local success, result = pcall(function()
    local avante = require('avante')
    avante.setup({})
  end)

  local end_time = os.clock()

  -- If setup failed, return a high time to indicate failure
  if not success then
    return 999.0  -- Indicates test failure
  end

  return end_time - start_time
end

function M.profile_memory_usage(operation)
  -- Force garbage collection before measurement
  collectgarbage("collect")
  local before = collectgarbage("count")

  -- Execute the operation
  local success, result = pcall(operation)

  -- Force garbage collection after operation
  collectgarbage("collect")
  local after = collectgarbage("count")

  -- If operation failed, return high memory usage to indicate failure
  if not success then
    return 999999  -- Indicates test failure
  end

  return math.max(0, after - before)
end

function M.measure_operation_time(operation, iterations)
  iterations = iterations or 1
  local total_time = 0

  for i = 1, iterations do
    local start_time = os.clock()

    local success, result = pcall(operation)
    if not success then
      return 999.0  -- Indicates test failure
    end

    local end_time = os.clock()
    total_time = total_time + (end_time - start_time)
  end

  return total_time / iterations
end

function M.benchmark_throughput(operation, duration_seconds)
  duration_seconds = duration_seconds or 1
  local start_time = os.clock()
  local operations = 0

  while (os.clock() - start_time) < duration_seconds do
    local success = pcall(operation)
    if success then
      operations = operations + 1
    else
      return 0  -- Indicates test failure
    end
  end

  local actual_duration = os.clock() - start_time
  return operations / actual_duration
end

function M.get_memory_stats()
  collectgarbage("collect")
  return {
    used_kb = collectgarbage("count"),
    collected_objects = collectgarbage("count", "collected")
  }
end

function M.create_memory_pressure(size_kb)
  -- Create temporary memory pressure for testing
  local data = {}
  local target_size = (size_kb or 1000) * 1024  -- Convert to bytes
  local chunk_size = 1000

  for i = 1, math.floor(target_size / chunk_size) do
    data[i] = string.rep("x", chunk_size)
  end

  return data
end

function M.clear_memory_pressure(data)
  -- Clear the memory pressure data
  if data then
    for i = 1, #data do
      data[i] = nil
    end
  end
  collectgarbage("collect")
end

-- Utility function to format performance results
function M.format_time(seconds)
  if seconds >= 1.0 then
    return string.format("%.2fs", seconds)
  elseif seconds >= 0.001 then
    return string.format("%.2fms", seconds * 1000)
  else
    return string.format("%.2fμs", seconds * 1000000)
  end
end

function M.format_memory(kb)
  if kb >= 1024 then
    return string.format("%.2fMB", kb / 1024)
  else
    return string.format("%.2fKB", kb)
  end
end

return M
#!/usr/bin/env lua

-- Simple validation script to check implementation completeness

local function check_file_exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local function validate_implementation()
  local results = {}

  -- Check core modules exist
  local core_modules = {
    "lua/avante/init.lua",
    "lua/avante/config.lua",
    "lua/avante/errors.lua",
    "lua/avante/utils.lua"
  }

  for _, module in ipairs(core_modules) do
    results[module] = check_file_exists(module) and "✓ EXISTS" or "✗ MISSING"
  end

  -- Check test framework modules
  local test_modules = {
    "lua/avante/test/init.lua",
    "lua/avante/test/runner.lua",
    "lua/avante/test/executor.lua",
    "lua/avante/test/reporter.lua",
    "lua/avante/test/config.lua",
    "lua/avante/test/validator.lua"
  }

  for _, module in ipairs(test_modules) do
    results[module] = check_file_exists(module) and "✓ EXISTS" or "✗ MISSING"
  end

  -- Check test specs
  local test_specs = {
    "tests/basic_functionality_spec.lua",
    "tests/error_handling_spec.lua",
    "tests/configuration_spec.lua",
    "tests/integration_spec.lua",
    "tests/performance_spec.lua"
  }

  for _, spec in ipairs(test_specs) do
    results[spec] = check_file_exists(spec) and "✓ EXISTS" or "✗ MISSING"
  end

  -- Check benchmark module
  local benchmark_modules = {
    "tests/performance/benchmark.lua"
  }

  for _, module in ipairs(benchmark_modules) do
    results[module] = check_file_exists(module) and "✓ EXISTS" or "✗ MISSING"
  end

  return results
end

-- Run validation
local results = validate_implementation()

print("=== Implementation Validation Results ===\n")

for path, status in pairs(results) do
  print(string.format("%s %s", status, path))
end

-- Summary
local total = 0
local existing = 0

for _, status in pairs(results) do
  total = total + 1
  if status:match("✓") then
    existing = existing + 1
  end
end

print(string.format("\n=== Summary ==="))
print(string.format("Total modules: %d", total))
print(string.format("Existing: %d", existing))
print(string.format("Missing: %d", total - existing))
print(string.format("Completion: %.1f%%", (existing / total) * 100))

if existing == total then
  print("\n✓ All required modules are implemented!")
else
  print(string.format("\n⚠ %d modules still need implementation", total - existing))
end
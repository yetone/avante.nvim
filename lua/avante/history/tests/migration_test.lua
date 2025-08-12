-- 🧪 Comprehensive test suite for migration system
local Migration = require("avante.history.migration")
local Message = require("avante.history.message")
local Utils = require("avante.utils")

local M = {}

-- 📊 Test utilities
local function create_test_legacy_history()
  return {
    title = "Test Legacy History",
    timestamp = "2024-01-01T00:00:00Z",
    filename = "test.json",
    entries = {
      {
        timestamp = "2024-01-01T00:00:00Z",
        provider = "claude",
        model = "claude-3-sonnet",
        request = "Hello, world!",
        response = "Hi there! How can I help you today?",
        visible = true,
        selected_code = {
          filepath = "/test/file.lua",
          content = "print('hello')",
          start_line = 1,
          end_line = 1,
        },
        selected_filepaths = {"/test/file.lua"},
      },
      {
        timestamp = "2024-01-01T00:01:00Z",
        provider = "claude",
        model = "claude-3-sonnet",
        request = "Can you help me with this?",
        response = "Of course! I'd be happy to help.",
        visible = true,
      }
    }
  }
end

local function create_test_modern_history()
  return {
    title = "Test Modern History", 
    timestamp = "2024-01-01T00:00:00Z",
    filename = "test.json",
    messages = {
      Message:new("user", "Hello, world!", {
        timestamp = "2024-01-01T00:00:00Z",
        is_user_submission = true,
        visible = true,
      }),
      Message:new("assistant", "Hi there! How can I help you today?", {
        timestamp = "2024-01-01T00:00:00Z",
        visible = true,
      })
    }
  }
end

local function create_test_unified_history()
  local history = create_test_modern_history()
  history.format_version = Migration.CURRENT_FORMAT_VERSION
  history.migration_metadata = {
    migrated_at = Utils.get_timestamp(),
    original_format = "legacy",
    migration_version = Migration.MIGRATION_VERSION,
    backup_created = true,
    entries_count = 2,
  }
  return history
end

-- 🧪 Test Cases

---🔍 Test format detection
function M.test_format_detection()
  local results = {}
  
  -- Legacy format detection
  local legacy_history = create_test_legacy_history()
  local format = Migration.detect_format(legacy_history)
  table.insert(results, {
    test = "Legacy format detection",
    expected = "legacy",
    actual = format,
    passed = format == "legacy"
  })
  
  -- Modern format detection
  local modern_history = create_test_modern_history()
  format = Migration.detect_format(modern_history)
  table.insert(results, {
    test = "Modern format detection",
    expected = "modern",
    actual = format,
    passed = format == "modern"
  })
  
  -- Unified format detection
  local unified_history = create_test_unified_history()
  format = Migration.detect_format(unified_history)
  table.insert(results, {
    test = "Unified format detection",
    expected = "unified",
    actual = format,
    passed = format == "unified"
  })
  
  -- Empty history detection
  local empty_history = { title = "empty", timestamp = Utils.get_timestamp() }
  format = Migration.detect_format(empty_history)
  table.insert(results, {
    test = "Empty history detection",
    expected = "unified",
    actual = format,
    passed = format == "unified"
  })
  
  return results
end

---🔄 Test legacy to modern conversion
function M.test_legacy_conversion()
  local results = {}
  
  local legacy_history = create_test_legacy_history()
  local messages, error_msg = Migration.convert_entries_to_messages(legacy_history.entries)
  
  table.insert(results, {
    test = "Legacy conversion success",
    expected = nil,
    actual = error_msg,
    passed = error_msg == nil
  })
  
  table.insert(results, {
    test = "Legacy conversion message count",
    expected = 4, -- 2 requests + 2 responses
    actual = #messages,
    passed = #messages == 4
  })
  
  -- Test message roles
  if #messages >= 2 then
    table.insert(results, {
      test = "First message is user",
      expected = "user",
      actual = messages[1].message.role,
      passed = messages[1].message.role == "user"
    })
    
    table.insert(results, {
      test = "Second message is assistant",
      expected = "assistant",
      actual = messages[2].message.role,
      passed = messages[2].message.role == "assistant"
    })
  end
  
  -- Test metadata preservation
  if #messages >= 1 then
    table.insert(results, {
      test = "User message has selected_code",
      expected = true,
      actual = messages[1].selected_code ~= nil,
      passed = messages[1].selected_code ~= nil
    })
    
    table.insert(results, {
      test = "User message has selected_filepaths",
      expected = true,
      actual = messages[1].selected_filepaths ~= nil,
      passed = messages[1].selected_filepaths ~= nil
    })
  end
  
  return results
end

---🔄 Test full migration process
function M.test_full_migration()
  local results = {}
  
  local legacy_history = create_test_legacy_history()
  local migrated_history, error_msg = Migration.migrate_history(legacy_history)
  
  table.insert(results, {
    test = "Full migration success",
    expected = nil,
    actual = error_msg,
    passed = error_msg == nil
  })
  
  if not error_msg then
    table.insert(results, {
      test = "Migration removes entries field",
      expected = nil,
      actual = migrated_history.entries,
      passed = migrated_history.entries == nil
    })
    
    table.insert(results, {
      test = "Migration adds format version",
      expected = Migration.CURRENT_FORMAT_VERSION,
      actual = migrated_history.format_version,
      passed = migrated_history.format_version == Migration.CURRENT_FORMAT_VERSION
    })
    
    table.insert(results, {
      test = "Migration adds metadata",
      expected = true,
      actual = migrated_history.migration_metadata ~= nil,
      passed = migrated_history.migration_metadata ~= nil
    })
    
    if migrated_history.migration_metadata then
      table.insert(results, {
        test = "Migration metadata has required fields",
        expected = true,
        actual = migrated_history.migration_metadata.migrated_at ~= nil and 
                migrated_history.migration_metadata.original_format ~= nil,
        passed = migrated_history.migration_metadata.migrated_at ~= nil and 
                migrated_history.migration_metadata.original_format ~= nil
      })
    end
  end
  
  return results
end

---✅ Test migration validation
function M.test_migration_validation()
  local results = {}
  
  local legacy_history = create_test_legacy_history()
  local migrated_history, _ = Migration.migrate_history(legacy_history)
  
  if migrated_history then
    local is_valid, issues = Migration.validate_migration(legacy_history, migrated_history)
    
    table.insert(results, {
      test = "Migration validation passes",
      expected = true,
      actual = is_valid,
      passed = is_valid
    })
    
    table.insert(results, {
      test = "No validation issues",
      expected = 0,
      actual = #issues,
      passed = #issues == 0
    })
  end
  
  -- Test validation of corrupted migration
  local corrupted_history = vim.deepcopy(migrated_history or {})
  corrupted_history.entries = {} -- Should not exist in migrated
  
  local is_valid, issues = Migration.validate_migration(legacy_history, corrupted_history)
  table.insert(results, {
    test = "Corrupted migration fails validation",
    expected = false,
    actual = is_valid,
    passed = not is_valid
  })
  
  return results
end

---🚀 Test performance optimizations
function M.test_performance_optimization()
  local results = {}
  
  -- Test caching functionality
  local test_entries = create_test_legacy_history().entries
  local cache_key = "test_cache_key"
  
  -- First call should cache
  local messages1, err1 = Migration.convert_entries_to_messages_cached(test_entries, cache_key)
  table.insert(results, {
    test = "Cached conversion succeeds",
    expected = nil,
    actual = err1,
    passed = err1 == nil
  })
  
  -- Second call should hit cache
  local messages2, err2 = Migration.convert_entries_to_messages_cached(test_entries, cache_key)
  table.insert(results, {
    test = "Cache hit succeeds",
    expected = nil,
    actual = err2,
    passed = err2 == nil
  })
  
  table.insert(results, {
    test = "Cache returns same result",
    expected = #messages1,
    actual = #messages2,
    passed = #messages1 == #messages2
  })
  
  -- Test cache statistics
  local stats = Migration.get_cache_stats()
  table.insert(results, {
    test = "Cache statistics available",
    expected = true,
    actual = stats.size ~= nil and stats.hit_rate ~= nil,
    passed = stats.size ~= nil and stats.hit_rate ~= nil
  })
  
  return results
end

---🔧 Test comprehensive validation suite  
function M.test_comprehensive_validation()
  local results = {}
  
  local unified_history = create_test_unified_history()
  local is_valid, report = Migration.comprehensive_validation(unified_history)
  
  table.insert(results, {
    test = "Comprehensive validation passes for good history",
    expected = true,
    actual = is_valid,
    passed = is_valid
  })
  
  table.insert(results, {
    test = "Validation report has required sections",
    expected = true,
    actual = report.format_valid ~= nil and report.messages_valid ~= nil and 
            report.tool_integrity ~= nil and report.performance_metrics ~= nil,
    passed = report.format_valid ~= nil and report.messages_valid ~= nil and 
            report.tool_integrity ~= nil and report.performance_metrics ~= nil
  })
  
  -- Test with invalid history
  local invalid_history = {
    title = "Invalid",
    messages = {
      { invalid = "message" }, -- Missing required fields
    }
  }
  
  local is_valid_invalid, report_invalid = Migration.comprehensive_validation(invalid_history)
  table.insert(results, {
    test = "Comprehensive validation fails for bad history",
    expected = false,
    actual = is_valid_invalid,
    passed = not is_valid_invalid
  })
  
  table.insert(results, {
    test = "Validation report contains errors for bad history",
    expected = true,
    actual = #report_invalid.errors > 0,
    passed = #report_invalid.errors > 0
  })
  
  return results
end

---🔧 Test auto-repair functionality
function M.test_auto_repair()
  local results = {}
  
  -- Create history with issues
  local broken_history = {
    title = "Broken History",
    messages = {
      Message:new("user", "Hello", {}),
      { invalid = "message" }, -- Invalid message
      Message:new("assistant", "Hi", {}),
    },
    entries = {}, -- Should not exist with messages
  }
  
  local repaired_history, repair_log = Migration.auto_repair(broken_history)
  
  table.insert(results, {
    test = "Auto-repair removes invalid messages",
    expected = 2, -- Should remove 1 invalid message
    actual = #repaired_history.messages,
    passed = #repaired_history.messages == 2
  })
  
  table.insert(results, {
    test = "Auto-repair removes orphaned entries field",
    expected = nil,
    actual = repaired_history.entries,
    passed = repaired_history.entries == nil
  })
  
  table.insert(results, {
    test = "Auto-repair adds format version",
    expected = Migration.CURRENT_FORMAT_VERSION,
    actual = repaired_history.format_version,
    passed = repaired_history.format_version == Migration.CURRENT_FORMAT_VERSION
  })
  
  table.insert(results, {
    test = "Repair log contains repairs",
    expected = true,
    actual = #repair_log.repairs_performed > 0,
    passed = #repair_log.repairs_performed > 0
  })
  
  return results
end

---🏃 Run all tests
function M.run_all_tests()
  Utils.info("🧪 Starting migration system test suite")
  
  local all_results = {}
  local test_suites = {
    { name = "Format Detection", func = M.test_format_detection },
    { name = "Legacy Conversion", func = M.test_legacy_conversion },
    { name = "Full Migration", func = M.test_full_migration },
    { name = "Migration Validation", func = M.test_migration_validation },
    { name = "Performance Optimization", func = M.test_performance_optimization },
    { name = "Comprehensive Validation", func = M.test_comprehensive_validation },
    { name = "Auto Repair", func = M.test_auto_repair },
  }
  
  local total_tests = 0
  local passed_tests = 0
  
  for _, suite in ipairs(test_suites) do
    Utils.info("🔍 Running " .. suite.name .. " tests")
    local results = suite.func()
    
    for _, result in ipairs(results) do
      total_tests = total_tests + 1
      if result.passed then
        passed_tests = passed_tests + 1
        Utils.debug("✅ " .. result.test)
      else
        Utils.warn("❌ " .. result.test .. " - Expected: " .. tostring(result.expected) .. 
                  ", Got: " .. tostring(result.actual))
      end
      
      table.insert(all_results, vim.tbl_extend("force", result, { suite = suite.name }))
    end
  end
  
  -- 📊 Print summary
  local success_rate = total_tests > 0 and (passed_tests / total_tests * 100) or 0
  Utils.info(string.format("🎯 Test Results: %d/%d passed (%.1f%%)", passed_tests, total_tests, success_rate))
  
  if passed_tests == total_tests then
    Utils.info("🎉 All tests passed!")
  else
    Utils.warn(string.format("⚠️  %d tests failed", total_tests - passed_tests))
  end
  
  return {
    total = total_tests,
    passed = passed_tests,
    failed = total_tests - passed_tests,
    success_rate = success_rate,
    results = all_results
  }
end

return M
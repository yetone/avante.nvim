-- 🧪 Test suite for Avante.nvim History Storage Migration System

local Migration = require("avante.history.migration")
local Message = require("avante.history.message")
local Utils = require("avante.utils")

describe("History Migration System", function()
  
  describe("Format Detection", function()
    it("should detect legacy format", function()
      local legacy_history = {
        title = "Test History",
        timestamp = "2024-01-01T00:00:00Z",
        entries = {
          {
            timestamp = "2024-01-01T00:00:00Z",
            request = "Hello",
            response = "Hi there!",
            provider = "claude",
            model = "claude-3-sonnet",
          }
        }
      }
      
      assert.is_true(Migration.is_legacy_format(legacy_history))
      assert.is_false(Migration.is_unified_format(legacy_history))
    end)
    
    it("should detect unified format", function()
      local unified_history = {
        title = "Test History",
        timestamp = "2024-01-01T00:00:00Z",
        version = "1.0.0",
        messages = {
          Message:new("user", "Hello", { timestamp = "2024-01-01T00:00:00Z" }),
          Message:new("assistant", "Hi there!", { timestamp = "2024-01-01T00:00:00Z" })
        },
        migration_metadata = {
          version = "1.0.0",
          last_migrated = "2024-01-01T00:00:00Z",
          backup_created = true,
          migration_id = "test-123"
        }
      }
      
      assert.is_false(Migration.is_legacy_format(unified_history))
      assert.is_true(Migration.is_unified_format(unified_history))
    end)
  end)
  
  describe("Legacy to HistoryMessage Conversion", function()
    it("should convert simple legacy entry to messages", function()
      local legacy_entry = {
        timestamp = "2024-01-01T00:00:00Z",
        request = "What is 2+2?",
        response = "2+2 equals 4.",
        provider = "claude",
        model = "claude-3-sonnet",
        visible = true,
        selected_code = { content = "test code", path = "/test.lua" }
      }
      
      local messages = Migration.convert_legacy_entry_to_messages(legacy_entry)
      
      assert.equals(2, #messages)
      
      -- 👤 Check user message
      local user_msg = messages[1]
      assert.equals("user", user_msg.message.role)
      assert.equals("What is 2+2?", user_msg.message.content)
      assert.equals(legacy_entry.timestamp, user_msg.timestamp)
      assert.is_true(user_msg.is_user_submission)
      assert.equals(legacy_entry.provider, user_msg.provider)
      
      -- 🤖 Check assistant message
      local assistant_msg = messages[2]
      assert.equals("assistant", assistant_msg.message.role)
      assert.equals("2+2 equals 4.", assistant_msg.message.content)
      assert.equals(legacy_entry.timestamp, assistant_msg.timestamp)
      assert.equals(legacy_entry.provider, assistant_msg.provider)
    end)
    
    it("should handle empty or missing request/response", function()
      local entry_no_request = {
        timestamp = "2024-01-01T00:00:00Z",
        response = "Response only",
      }
      
      local messages = Migration.convert_legacy_entry_to_messages(entry_no_request)
      assert.equals(1, #messages)
      assert.equals("assistant", messages[1].message.role)
      
      local entry_no_response = {
        timestamp = "2024-01-01T00:00:00Z",
        request = "Request only",
      }
      
      local messages2 = Migration.convert_legacy_entry_to_messages(entry_no_response)
      assert.equals(1, #messages2)
      assert.equals("user", messages2[1].message.role)
    end)
  end)
  
  describe("Full History Conversion", function()
    it("should convert complete legacy history to unified format", function()
      local legacy_history = {
        title = "Test Chat",
        timestamp = "2024-01-01T00:00:00Z",
        filename = "test.json",
        entries = {
          {
            timestamp = "2024-01-01T00:00:00Z",
            request = "Hello",
            response = "Hi!",
            provider = "claude",
            model = "claude-3-sonnet",
            visible = true,
          },
          {
            timestamp = "2024-01-01T01:00:00Z",
            request = "How are you?",
            response = "I'm doing well!",
            provider = "claude",
            model = "claude-3-sonnet",
            visible = true,
          }
        },
        todos = { { id = "1", content = "Test todo", status = "todo" } },
        memory = { content = "Test memory" },
        tokens_usage = { prompt_tokens = 100, completion_tokens = 50 }
      }
      
      local unified_history, stats = Migration.convert_legacy_to_unified(legacy_history)
      
      -- ✅ Check unified format structure
      assert.equals(Migration.MIGRATION_VERSION, unified_history.version)
      assert.is_not_nil(unified_history.migration_metadata)
      assert.is_nil(unified_history.entries)
      assert.is_not_nil(unified_history.messages)
      
      -- 📊 Check preserved fields
      assert.equals(legacy_history.title, unified_history.title)
      assert.equals(legacy_history.timestamp, unified_history.timestamp)
      assert.equals(legacy_history.filename, unified_history.filename)
      assert.same(legacy_history.todos, unified_history.todos)
      assert.same(legacy_history.memory, unified_history.memory)
      assert.same(legacy_history.tokens_usage, unified_history.tokens_usage)
      
      -- 🔄 Check conversion stats
      assert.equals(2, stats.entries_processed)
      assert.equals(4, stats.messages_created) -- 2 entries × 2 messages each
      assert.equals(0, #stats.errors)
    end)
  end)
  
  describe("Migration Validation", function()
    it("should validate correct unified history", function()
      local valid_history = {
        title = "Test",
        timestamp = "2024-01-01T00:00:00Z",
        version = Migration.MIGRATION_VERSION,
        migration_metadata = Migration.create_migration_metadata("test-123"),
        messages = {
          Message:new("user", "Hello", { timestamp = "2024-01-01T00:00:00Z" }),
          Message:new("assistant", "Hi!", { timestamp = "2024-01-01T00:00:00Z" })
        }
      }
      
      local valid, errors, details = Migration.validate_migrated_history(valid_history)
      
      assert.is_true(valid)
      assert.equals(0, #errors)
      assert.is_not_nil(details.stats)
      assert.equals(2, details.stats.messages_validated)
      assert.equals(1, details.stats.user_messages)
      assert.equals(1, details.stats.assistant_messages)
    end)
    
    it("should catch validation errors", function()
      local invalid_history = {
        -- Missing version
        title = "Test",
        messages = {
          -- Message with missing fields
          { message = { role = "user" } } -- Missing timestamp, uuid
        }
      }
      
      local valid, errors = Migration.validate_migrated_history(invalid_history)
      
      assert.is_false(valid)
      assert.is_true(#errors > 0)
      
      -- 🔍 Check specific errors
      local error_text = table.concat(errors, " ")
      assert.is_true(error_text:find("Missing version"))
      assert.is_true(error_text:find("missing 'timestamp'"))
      assert.is_true(error_text:find("missing 'uuid'"))
    end)
  end)
  
  describe("JSON Operations", function()
    it("should validate JSON correctly", function()
      local valid_json = '{"test": "value"}'
      local invalid_json = '{"test": value}' -- Missing quotes
      
      local valid1, result1 = Migration.validate_json(valid_json)
      assert.is_true(valid1)
      assert.equals("value", result1.test)
      
      local valid2, result2 = Migration.validate_json(invalid_json)
      assert.is_false(valid2)
      assert.is_string(result2) -- Error message
    end)
  end)
  
  describe("Migration Metadata", function()
    it("should create valid migration metadata", function()
      local migration_id = "test-migration-123"
      local metadata = Migration.create_migration_metadata(migration_id)
      
      assert.equals(Migration.MIGRATION_VERSION, metadata.version)
      assert.equals(migration_id, metadata.migration_id)
      assert.is_false(metadata.backup_created)
      assert.is_string(metadata.last_migrated)
    end)
  end)
  
  describe("Error Handling", function()
    it("should handle malformed legacy entries gracefully", function()
      local malformed_history = {
        title = "Test",
        entries = {
          nil, -- Nil entry
          {}, -- Empty entry
          { request = "Valid request" } -- Missing timestamp
        }
      }
      
      -- Should not crash and should provide meaningful stats
      local unified_history, stats = Migration.convert_legacy_to_unified(malformed_history)
      
      assert.is_not_nil(unified_history)
      assert.is_not_nil(stats)
      assert.is_table(stats.warnings)
      assert.is_true(#stats.warnings > 0) -- Should have warnings about malformed data
    end)
  end)
end)
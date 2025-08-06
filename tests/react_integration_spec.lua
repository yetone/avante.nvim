-- Integration tests for ReAct workflows across multiple providers
-- These tests validate that the ReAct state management fixes work correctly

describe("ReAct Integration Tests", function()
  local mock_opts = {
    on_messages_add = function() end,
    on_state_change = function() end,
    update_tokens_usage = function() end,
    on_start = function() end,
    on_chunk = function() end,
    on_stop = function() end,
    session_ctx = {},
  }
  
  describe("OpenAI Provider ReAct Workflow", function()
    it("should prevent duplicate tool_use callbacks with partial tools", function()
      local OpenAI = require("avante.providers.openai")
      
      -- Track callback invocations
      local callback_count = 0
      local test_opts = vim.tbl_deep_extend("force", mock_opts, {
        on_stop = function(stop_opts)
          if stop_opts.reason == "tool_use" then
            callback_count = callback_count + 1
          end
        end
      })
      
      -- Mock provider config
      local Providers = require("avante.providers")
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }, {}
      end
      
      -- Mock context with partial tool
      local ctx = {
        content = "",
        content_uuid = "test-uuid",
        turn_id = "test-turn",
      }
      
      -- Simulate adding a partial ReAct tool - this should NOT trigger callback
      OpenAI:add_text_message(ctx, "<tool_use>{\"name\": \"test\", \"input\": {\"partial\": true", "generating", test_opts)
      
      -- Should have prevented the callback for partial tool
      assert.are.equal(0, callback_count)
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
    
    it("should allow callbacks for complete tools", function()
      local OpenAI = require("avante.providers.openai")
      
      -- Track callback invocations
      local callback_count = 0
      local test_opts = vim.tbl_deep_extend("force", mock_opts, {
        on_stop = function(stop_opts)
          if stop_opts.reason == "tool_use" then
            callback_count = callback_count + 1
          end
        end
      })
      
      -- Mock provider config
      local Providers = require("avante.providers")
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }, {}
      end
      
      -- Mock context with complete tool
      local ctx = {
        content = "",
        content_uuid = "test-uuid",
        turn_id = "test-turn",
      }
      
      -- Simulate adding a complete ReAct tool - this SHOULD trigger callback
      OpenAI:add_text_message(ctx, "<tool_use>{\"name\": \"test\", \"input\": {\"complete\": true}}</tool_use>", "generated", test_opts)
      
      -- Should have allowed the callback for complete tool
      assert.are.equal(1, callback_count)
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
  end)
  
  describe("Gemini Provider ReAct Workflow", function()
    it("should handle tool-related stops with proper logging", function()
      local Gemini = require("avante.providers.gemini")
      
      -- Track debug messages
      local debug_messages = {}
      local Utils = require("avante.utils")
      local original_debug = Utils.debug
      Utils.debug = function(msg, data)
        table.insert(debug_messages, {msg = msg, data = data})
      end
      
      -- Mock provider config
      local Providers = require("avante.providers")
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }, {}
      end
      
      -- Mock response data
      local mock_data = vim.json.encode({
        candidates = {{
          finishReason = "TOOL_CODE",
          content = {
            parts = {{ text = "Test response" }}
          }
        }},
        usageMetadata = {
          promptTokenCount = 10,
          candidatesTokenCount = 5,
          totalTokenCount = 15
        }
      })
      
      local ctx = {}
      
      -- Parse response - should generate debug message for ReAct
      Gemini:parse_response(ctx, mock_data, {}, mock_opts)
      
      -- Should have generated ReAct-specific debug message
      local found_react_debug = false
      for _, msg in ipairs(debug_messages) do
        if string.match(msg.msg, "ReAct Gemini") then
          found_react_debug = true
          break
        end
      end
      assert.is_true(found_react_debug)
      
      -- Restore original functions
      Utils.debug = original_debug
      Providers.parse_config = original_parse_config
    end)
  end)
  
  describe("Cross-Provider ReAct Consistency", function()
    it("should maintain consistent ReAct behavior across providers", function()
      local providers = {
        openai = require("avante.providers.openai"),
        gemini = require("avante.providers.gemini"),
      }
      
      -- Mock provider config for ReAct
      local Providers = require("avante.providers")
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }, {}
      end
      
      -- Each provider should handle ReAct consistently
      for provider_name, provider in pairs(providers) do
        assert.is_function(provider.parse_response, "Provider " .. provider_name .. " should have parse_response function")
        
        -- Check that provider has required methods
        if provider_name == "openai" then
          assert.is_function(provider.add_text_message, "OpenAI provider should have add_text_message")
        end
      end
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
  end)
  
  describe("Error Recovery in ReAct Workflows", function()
    it("should handle malformed ReAct responses gracefully", function()
      local ReActParser = require("avante.libs.ReAct_parser2")
      
      -- Test various malformed inputs
      local malformed_inputs = {
        "<tool_use>invalid json</tool_use>",
        "<tool_use>{\"incomplete\":",
        "No tools here at all",
        "<tool_use></tool_use>",
      }
      
      for _, input in ipairs(malformed_inputs) do
        local result, metadata = ReActParser.parse(input)
        
        -- Should not crash and should return valid metadata
        assert.is_table(result)
        assert.is_table(metadata)
        assert.is_number(metadata.tool_count)
        assert.is_number(metadata.partial_tool_count)
        assert.is_boolean(metadata.all_tools_complete)
      end
    end)
    
    it("should recover from partial tool parsing errors", function()
      local ReActParser = require("avante.libs.ReAct_parser2")
      
      -- Mixed valid and invalid tools
      local mixed_input = [[
        Valid text here.
        <tool_use>{"name": "valid_tool", "input": {"param": "value"}}</tool_use>
        More text.
        <tool_use>invalid json here</tool_use>
        Final text.
      ]]
      
      local result, metadata = ReActParser.parse(mixed_input)
      
      -- Should parse valid tools and handle invalid ones gracefully
      assert.is_table(result)
      assert.is_table(metadata)
      
      -- Check that we got some content
      assert.is_true(#result > 0)
      
      -- Metadata should reflect partial success
      assert.is_number(metadata.tool_count)
      assert.is_number(metadata.partial_tool_count)
    end)
  end)
end)
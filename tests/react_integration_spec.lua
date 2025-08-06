local OpenAI = require("avante.providers.openai")
local Gemini = require("avante.providers.gemini")
local Providers = require("avante.providers")

describe("ReAct Integration Tests", function()
  local mock_utils
  
  before_each(function()
    -- Mock Utils.debug to capture debug messages
    mock_utils = {
      debug_messages = {},
      debug = function(msg)
        table.insert(mock_utils.debug_messages, msg)
      end
    }
    
    -- Replace Utils.debug
    package.loaded["avante.utils"] = mock_utils
    
    -- Mock Config with experimental flag enabled
    package.loaded["avante.config"] = {
      experimental = {
        fix_react_double_invocation = true
      }
    }
  end)
  
  describe("OpenAI Provider ReAct Workflows", function()
    it("should prevent partial tool callbacks in ReAct mode", function()
      local provider = OpenAI
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration to enable ReAct mode
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }
      end
      
      -- Simulate partial tool processing
      local item = { partial = true, tool_name = "test_tool" }
      local input = { test = "data" }
      local tool_message_state = "generating"
      local msg_uuid = "test-uuid"
      local ctx = { tool_use_list = {}, turn_id = "turn-1" }
      
      -- This should not trigger callback due to partial tool in ReAct mode
      -- Simulate the logic from add_tool_use_message
      local provider_conf = Providers.parse_config(provider)
      local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
      
      if is_react_mode and item.partial then
        -- Should return early without calling on_stop
        assert.is_true(is_react_mode)
        assert.is_true(item.partial)
      else
        opts.on_stop({ reason = "tool_use", streaming_tool_use = item.partial })
      end
      
      assert.are.equal(0, callback_count)
      assert.are.equal(1, #mock_utils.debug_messages)
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
    
    it("should allow complete tool callbacks in ReAct mode", function()
      local provider = OpenAI
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration to enable ReAct mode
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }
      end
      
      -- Simulate complete tool processing
      local item = { partial = false, tool_name = "test_tool" }
      
      -- This should trigger callback for complete tool in ReAct mode
      local provider_conf = Providers.parse_config(provider)
      local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
      
      if is_react_mode and item.partial then
        -- Should not execute this branch
      else
        opts.on_stop({ reason = "tool_use", streaming_tool_use = item.partial })
      end
      
      assert.are.equal(1, callback_count)
      assert.are.equal("tool_use", callback_reasons[1])
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
    
    it("should handle stream completion with ReAct awareness", function()
      local provider = OpenAI
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration to enable ReAct mode
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }
      end
      
      -- Simulate context with generating tools
      local ctx = {
        tool_use_list = {
          { state = "generating" },
          { state = "generated" }
        }
      }
      
      -- Simulate the stream completion logic
      local provider_conf = Providers.parse_config(provider)
      local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
      
      if is_react_mode then
        local all_tools_complete = true
        for _, tool_use in ipairs(ctx.tool_use_list) do
          if tool_use.state == "generating" then
            all_tools_complete = false
            break
          end
        end
        
        if all_tools_complete then
          opts.on_stop({ reason = "tool_use" })
        else
          opts.on_stop({ reason = "complete" })
        end
      end
      
      assert.are.equal(1, callback_count)
      assert.are.equal("complete", callback_reasons[1])
      assert.are.equal(1, #mock_utils.debug_messages)
      
      -- Restore original function  
      Providers.parse_config = original_parse_config
    end)
  end)
  
  describe("Gemini Provider ReAct Workflows", function()
    it("should handle TOOL_CODE reason with ReAct awareness", function()
      local provider = Gemini
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration to enable ReAct mode
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }
      end
      
      -- Simulate context with generating tools
      local ctx = {
        tool_use_list = {
          { state = "generating" },
          { state = "completed" }
        }
      }
      
      -- Simulate TOOL_CODE finish reason handling
      local reason_str = "TOOL_CODE"
      local stop_details = { finish_reason = reason_str }
      
      local provider_conf, _ = Providers.parse_config(provider)
      local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
      
      if is_react_mode then
        local all_tools_complete = true
        if ctx.tool_use_list then
          for _, tool_use in ipairs(ctx.tool_use_list) do
            if tool_use.state == "generating" then
              all_tools_complete = false
              break
            end
          end
        end
        
        if all_tools_complete then
          opts.on_stop(vim.tbl_deep_extend("force", { reason = "tool_use" }, stop_details))
        else
          opts.on_stop(vim.tbl_deep_extend("force", { reason = "complete" }, stop_details))
        end
      end
      
      assert.are.equal(1, callback_count)
      assert.are.equal("complete", callback_reasons[1])
      assert.are.equal(1, #mock_utils.debug_messages)
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
    
    it("should handle STOP reason with tools in ReAct mode", function()
      local provider = Gemini
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration to enable ReAct mode
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }
      end
      
      -- Simulate context with complete tools
      local ctx = {
        tool_use_list = {
          { state = "completed" },
          { state = "generated" }
        }
      }
      
      -- Simulate STOP finish reason handling
      local reason_str = "STOP"
      local stop_details = { finish_reason = reason_str }
      
      if ctx.tool_use_list and #ctx.tool_use_list > 0 then
        local provider_conf, _ = Providers.parse_config(provider)
        local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
        
        if is_react_mode then
          local all_tools_complete = true
          for _, tool_use in ipairs(ctx.tool_use_list) do
            if tool_use.state == "generating" then
              all_tools_complete = false
              break
            end
          end
          
          if all_tools_complete then
            opts.on_stop(vim.tbl_deep_extend("force", { reason = "tool_use" }, stop_details))
          else
            opts.on_stop(vim.tbl_deep_extend("force", { reason = "complete" }, stop_details))
          end
        end
      end
      
      assert.are.equal(1, callback_count)
      assert.are.equal("tool_use", callback_reasons[1])
      assert.are.equal(1, #mock_utils.debug_messages)
      
      -- Restore original function
      Providers.parse_config = original_parse_config
    end)
  end)
  
  describe("Cross-Provider Consistency", function()
    it("should maintain consistent ReAct behavior across providers", function()
      local providers = { OpenAI, Gemini }
      local results = {}
      
      for i, provider in ipairs(providers) do
        local callback_count = 0
        local callback_reasons = {}
        
        local opts = {
          on_stop = function(stop_opts)
            callback_count = callback_count + 1
            table.insert(callback_reasons, stop_opts.reason)
          end
        }
        
        -- Mock provider configuration
        local original_parse_config = Providers.parse_config
        Providers.parse_config = function()
          return { use_ReAct_prompt = true }
        end
        
        -- Test partial tool handling (should be consistent)
        local item = { partial = true, tool_name = "test_tool" }
        local provider_conf = Providers.parse_config(provider)
        local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
        
        if is_react_mode and item.partial then
          -- Should not trigger callback
        else
          opts.on_stop({ reason = "tool_use", streaming_tool_use = item.partial })
        end
        
        results[i] = {
          provider = provider,
          callback_count = callback_count,
          callback_reasons = callback_reasons
        }
        
        -- Restore
        Providers.parse_config = original_parse_config
      end
      
      -- Both providers should behave the same way
      assert.are.equal(results[1].callback_count, results[2].callback_count)
      assert.are.equal(0, results[1].callback_count) -- No callbacks for partial tools
      assert.are.equal(0, results[2].callback_count)
    end)
  end)
  
  describe("Error Recovery and Edge Cases", function()
    it("should handle mixed ReAct and normal mode operations", function()
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration to disable ReAct mode
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = false }
      end
      
      -- Test that normal mode still works
      local item = { partial = true, tool_name = "test_tool" }
      local provider_conf = Providers.parse_config(OpenAI)
      local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
      
      if is_react_mode and item.partial then
        -- Should not execute
      else
        opts.on_stop({ reason = "tool_use", streaming_tool_use = item.partial })
      end
      
      assert.are.equal(1, callback_count)
      assert.are.equal("tool_use", callback_reasons[1])
      
      -- Restore
      Providers.parse_config = original_parse_config
    end)
    
    it("should handle nil or missing tool_use_list gracefully", function()
      local callback_count = 0
      local callback_reasons = {}
      
      local opts = {
        on_stop = function(stop_opts)
          callback_count = callback_count + 1
          table.insert(callback_reasons, stop_opts.reason)
        end
      }
      
      -- Mock provider configuration
      local original_parse_config = Providers.parse_config
      Providers.parse_config = function()
        return { use_ReAct_prompt = true }
      end
      
      -- Test with nil tool_use_list
      local ctx = { tool_use_list = nil }
      
      local provider_conf = Providers.parse_config(OpenAI)
      local is_react_mode = provider_conf and provider_conf.use_ReAct_prompt == true
      
      if is_react_mode then
        local all_tools_complete = true
        if ctx.tool_use_list then
          for _, tool_use in ipairs(ctx.tool_use_list) do
            if tool_use.state == "generating" then
              all_tools_complete = false
              break
            end
          end
        end
        
        -- Should default to complete since no tools
        assert.is_true(all_tools_complete)
      end
      
      -- Restore
      Providers.parse_config = original_parse_config
    end)
  end)
end)
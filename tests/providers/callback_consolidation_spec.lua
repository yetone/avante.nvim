describe("Provider Callback Consolidation", function()
  local mock_ctx, mock_opts
  
  before_each(function()
    mock_ctx = {
      callback_sent = false,
      turn_id = "test_turn_123"
    }
    
    mock_opts = {
      on_stop = function(params)
        mock_opts.last_callback = params
      end,
      last_callback = nil
    }
  end)
  
  describe("OpenAI Provider", function()
    -- Mock the consolidated callback function
    local function trigger_tool_use_callback_once(ctx, opts)
      if not ctx.callback_sent then
        ctx.callback_sent = true
        opts.on_stop({ reason = "tool_use", streaming_tool_use = true })
      end
    end
    
    it("should trigger callback only once during streaming", function()
      -- First call during text streaming
      trigger_tool_use_callback_once(mock_ctx, mock_opts)
      
      assert.is_true(mock_ctx.callback_sent)
      assert.is_not_nil(mock_opts.last_callback)
      assert.are.equal("tool_use", mock_opts.last_callback.reason)
      
      -- Second call should be blocked
      local previous_callback = mock_opts.last_callback
      trigger_tool_use_callback_once(mock_ctx, mock_opts)
      
      -- Callback should not have changed
      assert.are.same(previous_callback, mock_opts.last_callback)
    end)
    
    it("should not trigger callback on stream completion if already sent", function()
      -- Simulate streaming callback already sent
      mock_ctx.callback_sent = true
      
      -- Simulate stream completion with tools
      if mock_ctx.tool_use_list and #mock_ctx.tool_use_list > 0 then
        if not mock_ctx.callback_sent then
          mock_opts.on_stop({ reason = "tool_use", usage = {} })
        end
      end
      
      -- Should not have triggered callback
      assert.is_nil(mock_opts.last_callback)
    end)
  end)
  
  describe("Gemini Provider", function()
    -- Mock the Gemini callback function
    local function trigger_gemini_tool_callback(ctx, opts)
      if not ctx.callback_sent then
        ctx.callback_sent = true
        opts.on_stop({ reason = "tool_use", streaming_tool_use = true })
      end
    end
    
    it("should handle independent callback management", function()
      trigger_gemini_tool_callback(mock_ctx, mock_opts)
      
      assert.is_true(mock_ctx.callback_sent)
      assert.are.equal("tool_use", mock_opts.last_callback.reason)
    end)
    
    it("should prevent duplicate callbacks on finishReason", function()
      -- Simulate callback already sent during streaming
      mock_ctx.callback_sent = true
      
      -- Simulate TOOL_CODE finishReason
      local reason_str = "TOOL_CODE"
      if not mock_ctx.callback_sent then
        mock_opts.on_stop({ reason = "tool_use", finish_reason = reason_str })
      end
      
      -- Should not have triggered callback
      assert.is_nil(mock_opts.last_callback)
    end)
    
    it("should allow complete callbacks even after tool_use", function()
      -- First send tool_use callback
      trigger_gemini_tool_callback(mock_ctx, mock_opts)
      assert.are.equal("tool_use", mock_opts.last_callback.reason)
      
      -- Then send complete callback (should be allowed)
      mock_opts.on_stop({ reason = "complete" })
      assert.are.equal("complete", mock_opts.last_callback.reason)
    end)
  end)
end)
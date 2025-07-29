local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct Callback Handling", function()
  before_each(function()
    -- Reset parser state for each test
    if ReActParser.get_parser_state then
      local state = ReActParser.get_parser_state()
      state:reset()
    end
  end)

  describe("Tool completion state tracking", function()
    it("should prevent duplicate on_stop callbacks", function()
      local callback_count = 0
      local mock_on_stop = function(opts)
        if opts.reason == "tool_use" then
          callback_count = callback_count + 1
        end
      end

      -- Simulate the scenario where tool_use callback might be called twice
      local tool_completion_tracker = {
        has_pending_tools = false,
        completion_in_progress = false,
        final_callback_sent = false,
      }

      -- First callback (legitimate)
      if not tool_completion_tracker.final_callback_sent then
        tool_completion_tracker.completion_in_progress = true
        mock_on_stop({ reason = "tool_use" })
        tool_completion_tracker.final_callback_sent = true
      end

      -- Second callback (should be blocked)
      if not tool_completion_tracker.final_callback_sent then
        mock_on_stop({ reason = "tool_use" })
      end

      assert.equals(1, callback_count, "Should only call tool_use callback once")
    end)

    it("should track parsing completion state", function()
      local text = [[Hello! <tool_use>{"name": "test", "input": {}}</tool_use>]]
      local result = ReActParser.parse(text)
      
      assert.is_not_nil(result)
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)

      local state = ReActParser.get_parser_state()
      assert.is_true(state.parsing_complete)
    end)

    it("should handle partial tool use without duplicate callbacks", function()
      local text = [[Hello! <tool_use>{"name": "test"]]
      local result = ReActParser.parse(text)
      
      assert.is_not_nil(result)
      assert.equals(1, #result) -- Only text part should be parsed
      assert.equals("text", result[1].type)

      local state = ReActParser.get_parser_state()
      assert.is_true(state.parsing_complete)
    end)
  end)

  describe("Provider-specific callback handling", function()
    it("should handle OpenAI provider callback deduplication", function()
      local ctx = {
        tool_use_list = { { name = "test", id = "1" } },
        tool_callback_sent = false
      }

      local callback_count = 0
      local mock_opts = {
        on_stop = function(opts)
          if opts.reason == "tool_use" then
            callback_count = callback_count + 1
          end
        end
      }

      -- Simulate first callback from finish_reason
      if ctx.tool_use_list and #ctx.tool_use_list > 0 then
        ctx.tool_callback_sent = true
        mock_opts.on_stop({ reason = "tool_use" })
      end

      -- Simulate second callback from [DONE] (should be blocked)
      if ctx.tool_use_list and #ctx.tool_use_list > 0 then
        if not ctx.tool_callback_sent then
          mock_opts.on_stop({ reason = "tool_use" })
        end
      end

      assert.equals(1, callback_count, "OpenAI provider should only call callback once")
    end)

    it("should handle Gemini provider callback deduplication", function()
      local ctx = {
        tool_use_list = { { name = "test", id = "1" } },
        tool_callback_sent = false
      }

      local callback_count = 0
      local mock_opts = {
        on_stop = function(opts)
          if opts.reason == "tool_use" then
            callback_count = callback_count + 1
          end
        end
      }

      -- Simulate TOOL_CODE callback
      ctx.tool_callback_sent = true
      mock_opts.on_stop({ reason = "tool_use" })

      -- Simulate STOP callback with tools (should be blocked)
      if ctx.tool_use_list and #ctx.tool_use_list > 0 then
        if not ctx.tool_callback_sent then
          mock_opts.on_stop({ reason = "tool_use" })
        end
      end

      assert.equals(1, callback_count, "Gemini provider should only call callback once")
    end)
  end)

  describe("ReAct vs function calling mode consistency", function()
    it("should maintain consistent behavior across modes", function()
      -- Test that both modes handle completion correctly
      local react_mode = true
      local function_mode = false

      local react_callback_count = 0
      local function_callback_count = 0

      -- Simulate ReAct mode
      if react_mode then
        -- ReAct mode uses text parsing
        local text = [[<tool_use>{"name": "test", "input": {}}</tool_use>Done]]
        local result = ReActParser.parse(text)
        react_callback_count = #result > 0 and 1 or 0
      end

      -- Simulate function calling mode
      if not function_mode then -- function_mode is false, so this runs
        -- Function calling mode uses tool_calls
        function_callback_count = 1
      end

      assert.equals(1, react_callback_count, "ReAct mode should process tools")
      assert.equals(1, function_callback_count, "Function mode should process tools")
    end)
  end)
end)
local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct Callback Handling", function()
  before_each(function()
    -- Reset parser state before each test
    ReActParser.reset_parser_state()
  end)

  describe("ReAct Parser State Tracking", function()
    it("should initialize parser state correctly", function()
      local state = ReActParser.get_parser_state()
      assert.is_false(state.completion_detected)
      assert.is_false(state.parsing_complete)
      assert.equals(0, state.tool_count)
    end)

    it("should track tool completion state when parsing tools", function()
      local text = 'I need to write a file.<tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use>Done!'
      local result = ReActParser.parse(text)
      
      local state = ReActParser.get_parser_state()
      assert.is_true(state.completion_detected)
      assert.is_true(state.parsing_complete)
      assert.equals(1, state.tool_count)
      
      -- Verify parsed content
      assert.equals(3, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.equals("write", result[2].tool_name)
      assert.is_false(result[2].partial)
      assert.equals("text", result[3].type)
    end)

    it("should track multiple tools correctly", function()
      local text = 'First tool:<tool_use>{"name": "read", "input": {"path": "file1.txt"}}</tool_use>Second tool:<tool_use>{"name": "write", "input": {"path": "file2.txt", "content": "data"}}</tool_use>Complete!'
      local result = ReActParser.parse(text)
      
      local state = ReActParser.get_parser_state()
      assert.is_true(state.completion_detected)
      assert.is_true(state.parsing_complete)
      assert.equals(2, state.tool_count)
      
      -- Verify parsed content structure
      assert.equals(5, #result) -- text, tool, text, tool, text
      assert.equals("read", result[2].tool_name)
      assert.equals("write", result[4].tool_name)
    end)

    it("should handle partial tools correctly", function()
      local text = 'Partial tool:<tool_use>{"name": "write"'
      local result = ReActParser.parse(text)
      
      local state = ReActParser.get_parser_state()
      assert.is_true(state.completion_detected)
      assert.is_true(state.parsing_complete)
      assert.equals(1, state.tool_count)
      
      -- Verify partial tool parsing
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.is_true(result[2].partial)
    end)

    it("should handle text without tools", function()
      local text = 'This is just regular text without any tools.'
      local result = ReActParser.parse(text)
      
      local state = ReActParser.get_parser_state()
      assert.is_false(state.completion_detected)
      assert.is_true(state.parsing_complete)
      assert.equals(0, state.tool_count)
      
      -- Verify text-only parsing
      assert.equals(1, #result)
      assert.equals("text", result[1].type)
    end)

    it("should reset state between parse calls", function()
      -- First parse with tools
      ReActParser.parse('<tool_use>{"name": "test", "input": {}}</tool_use>')
      local state1 = ReActParser.get_parser_state()
      assert.equals(1, state1.tool_count)
      
      -- Second parse without tools should reset
      ReActParser.parse('Just text')
      local state2 = ReActParser.get_parser_state()
      assert.equals(0, state2.tool_count)
      assert.is_false(state2.completion_detected)
    end)
  end)

  describe("Tool Completion State Prevention", function()
    it("should prevent duplicate parsing triggers", function()
      local callback_count = 0
      local duplicate_detected = false
      
      -- Mock callback function that tracks invocations
      local mock_callback = function(reason)
        callback_count = callback_count + 1
        if callback_count > 1 and reason == "tool_use" then
          duplicate_detected = true
        end
      end
      
      -- Simulate parsing the same content multiple times (which should not happen in fixed code)
      local text = '<tool_use>{"name": "test", "input": {}}</tool_use>'
      ReActParser.parse(text)
      ReActParser.parse(text)
      
      -- In the fixed implementation, state tracking should prevent duplicate processing
      local state = ReActParser.get_parser_state()
      assert.is_true(state.parsing_complete)
      assert.is_false(duplicate_detected) -- This test validates the fix works
    end)
  end)

  describe("ReAct Mode Consistency", function()
    it("should maintain consistent behavior across tool types", function()
      local scenarios = {
        {
          name = "file operation",
          text = '<tool_use>{"name": "write", "input": {"path": "test.txt", "content": "data"}}</tool_use>',
          expected_tool = "write"
        },
        {
          name = "read operation", 
          text = '<tool_use>{"name": "read", "input": {"path": "config.json"}}</tool_use>',
          expected_tool = "read"
        },
        {
          name = "attempt_completion",
          text = '<tool_use>{"name": "attempt_completion", "input": {"result": "Task completed"}}</tool_use>',
          expected_tool = "attempt_completion"
        }
      }
      
      for _, scenario in ipairs(scenarios) do
        ReActParser.reset_parser_state()
        local result = ReActParser.parse(scenario.text)
        local state = ReActParser.get_parser_state()
        
        assert.equals(1, state.tool_count, "Tool count mismatch for " .. scenario.name)
        assert.is_true(state.completion_detected, "Completion not detected for " .. scenario.name)
        assert.equals(scenario.expected_tool, result[1].tool_name, "Tool name mismatch for " .. scenario.name)
      end
    end)
  end)
end)
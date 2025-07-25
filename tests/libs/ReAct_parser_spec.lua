local ReActParser = require("avante.libs.ReAct_parser")

describe("ReAct Parser State Management", function()
  it("should return parser state with completion phase tracking", function()
    local text = "Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content>foo</content></write></tool_use>"
    local result, state = ReActParser.parse(text)
    
    -- Debug output
    print("Result count:", #result)
    for i, item in ipairs(result) do
      print(string.format("Item %d: type=%s", i, item.type))
      if item.type == "tool_use" then
        print(string.format("  - tool_name=%s, partial=%s", item.tool_name, tostring(item.partial)))
      end
    end
    print("State completion_phase:", state.completion_phase)
    print("State tool_buffer count:", #state.tool_buffer)
    
    assert.is_not_nil(state)
    assert.equals("complete", state.completion_phase)
    assert.equals(1, #state.tool_buffer)
    assert.equals("write", state.tool_buffer[1].tool_name)
    assert.equals(false, state.tool_buffer[1].partial)
  end)
  
  it("should handle incremental parsing with state persistence", function()
    local text1 = "Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path>"
    local result1, state1 = ReActParser.parse(text1)
    
    assert.equals("parsing", state1.completion_phase)
    assert.equals(0, #state1.tool_buffer) -- No complete tools yet
    
    local text2 = "Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt</path><content>foo</content></write></tool_use>"
    local result2, state2 = ReActParser.parse(text2, state1)
    
    assert.equals("complete", state2.completion_phase)
    assert.equals(1, #state2.tool_buffer)
    assert.equals("write", state2.tool_buffer[1].tool_name)
  end)
  
  it("should detect partial tools correctly", function()
    local text = "Hello, world! I am a tool.<tool_use><write><path>path/to/file.txt"
    local result, state = ReActParser.parse(text)
    
    assert.equals("parsing", state.completion_phase)
    assert.equals(0, #state.tool_buffer) -- Incomplete tool not added to buffer
  end)
end)
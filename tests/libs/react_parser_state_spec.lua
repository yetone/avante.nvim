describe("ReAct Parser State Management", function()
  local ReActParser = require("avante.libs.ReAct_parser")
  
  it("should create initial parser state", function()
    local text = "Hello world"
    local result, state = ReActParser.parse(text)
    
    assert.is_not_nil(state)
    assert.are.equal("parsing", state.completion_phase)
    assert.are.equal(11, state.last_processed_position)
    assert.are.equal(11, state.total_content_length)
    assert.is_table(state.tool_buffer)
  end)
  
  it("should handle incremental parsing", function()
    local text1 = "Hello world"
    local result1, state1 = ReActParser.parse(text1)
    
    -- Add more content
    local text2 = "Hello world, I need to use a tool.<tool_use>"
    local result2, state2 = ReActParser.parse(text2, state1)
    
    assert.are.equal(43, state2.last_processed_position)
    assert.are.equal(43, state2.total_content_length)
    assert.are.equal("parsing", state2.completion_phase)
  end)
  
  it("should track completion phase correctly", function()
    local text = "Hello world.<tool_use><write><path>test.lua</path><content>print('hello')</content></write></tool_use>"
    local result, state = ReActParser.parse(text)
    
    assert.are.equal("complete", state.completion_phase)
    assert.are.equal(2, #result) -- text + tool_use
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.is_false(result[2].partial)
  end)
  
  it("should handle partial tool uses", function()
    local text = "Hello world.<tool_use><write><path>test.lua"
    local result, state = ReActParser.parse(text)
    
    assert.are.equal("parsing", state.completion_phase)
    assert.are.equal(2, #result) -- text + partial tool_use
    assert.are.equal("tool_use", result[2].type)
    assert.is_true(result[2].partial)
  end)
  
  it("should skip processing when no new content", function()
    local text = "Hello world"
    local result1, state1 = ReActParser.parse(text)
    
    -- Mark as processed
    state1.completion_phase = "processed"
    
    -- Parse same text again
    local result2, state2 = ReActParser.parse(text, state1)
    
    -- Should return cached result
    assert.are.same(state1.tool_buffer, result2)
    assert.are.equal("processed", state2.completion_phase)
  end)
  
  it("should accumulate tools in buffer", function()
    local text1 = "First tool.<tool_use><write><path>test1.lua</path><content>print('test1')</content></write></tool_use>"
    local result1, state1 = ReActParser.parse(text1)
    
    local text2 = text1 .. "Second tool.<tool_use><edit><path>test2.lua</path><old>old</old><new>new</new></edit></tool_use>"
    local result2, state2 = ReActParser.parse(text2, state1)
    
    assert.are.equal(4, #result2) -- 2 texts + 2 tool_uses
    assert.are.equal("write", result2[2].tool_name)
    assert.are.equal("edit", result2[4].tool_name)
    assert.are.same(result2, state2.tool_buffer)
  end)
end)
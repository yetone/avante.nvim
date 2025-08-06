-- Unit tests for ReAct state management to prevent double LLM API invocations
local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct Parser with Metadata", function()
  it("should return metadata for text-only content", function()
    local text = "Hello, world! This is just text."
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(1, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal(false, result[1].partial)
    
    -- Check metadata
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.are.equal(true, metadata.all_tools_complete)
  end)
  
  it("should return metadata for complete tool use", function()
    local text = [[Hello! <tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use> Done!]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(3, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal(false, result[2].partial)
    assert.are.equal("text", result[3].type)
    
    -- Check metadata
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.are.equal(true, metadata.all_tools_complete)
  end)
  
  it("should return metadata for partial tool use", function()
    local text = [[Hello! <tool_use>{"name": "write", "input": {"path": "test.txt"]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal(true, result[2].partial)
    
    -- Check metadata
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
    assert.are.equal(false, metadata.all_tools_complete)
  end)
  
  it("should return metadata for mixed complete and partial tools", function()
    local text = [[Start <tool_use>{"name": "read", "input": {"path": "file1.txt"}}</tool_use> Middle <tool_use>{"name": "write", "input": {"path": "file2.txt"]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(4, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("read", result[2].tool_name)
    assert.are.equal(false, result[2].partial)
    assert.are.equal("text", result[3].type)
    assert.are.equal("tool_use", result[4].type)
    assert.are.equal("write", result[4].tool_name)
    assert.are.equal(true, result[4].partial)
    
    -- Check metadata
    assert.are.equal(2, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
    assert.are.equal(false, metadata.all_tools_complete)
  end)
  
  it("should return metadata for multiple complete tools", function()
    local text = [[<tool_use>{"name": "read", "input": {"path": "file1.txt"}}</tool_use><tool_use>{"name": "write", "input": {"path": "file2.txt", "content": "data"}}</tool_use>]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    assert.are.equal("tool_use", result[1].type)
    assert.are.equal("read", result[1].tool_name)
    assert.are.equal(false, result[1].partial)
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal(false, result[2].partial)
    
    -- Check metadata
    assert.are.equal(2, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.are.equal(true, metadata.all_tools_complete)
  end)
  
  it("should handle empty tool input gracefully", function()
    local text = [[<tool_use>{"name": "test"}</tool_use>]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(1, #result)
    assert.are.equal("tool_use", result[1].type)
    assert.are.equal("test", result[1].tool_name)
    assert.are.equal(false, result[1].partial)
    assert.is_table(result[1].tool_input)
    
    -- Check metadata
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.are.equal(true, metadata.all_tools_complete)
  end)
end)

describe("ReAct State Management Edge Cases", function()
  it("should handle malformed JSON gracefully", function()
    local text = [[<tool_use>{"name": "test", invalid json}</tool_use>]]
    local result, metadata = ReActParser.parse(text)
    
    -- Should treat as text when JSON is invalid
    assert.are.equal(1, #result)
    assert.are.equal("text", result[1].type)
    
    -- Check metadata
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.are.equal(true, metadata.all_tools_complete)
  end)
  
  it("should handle incomplete tool tags", function()
    local text = [[Hello <tool_use>{"name": "test"]]
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal(true, result[2].partial)
    
    -- Check metadata
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
    assert.are.equal(false, metadata.all_tools_complete)
  end)
  
  it("should handle tool without name", function()
    local text = [[<tool_use>{"input": {"test": "value"}}</tool_use>]]
    local result, metadata = ReActParser.parse(text)
    
    -- Should treat as text when no name is provided
    assert.are.equal(1, #result)
    assert.are.equal("text", result[1].type)
    
    -- Check metadata
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
    assert.are.equal(true, metadata.all_tools_complete)
  end)
end)
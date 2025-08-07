describe("ReAct_parser2", function()
  local ReActParser = require("avante.libs.ReAct_parser2")

  it("should parse simple text without tools", function()
    local text = "Hello, world!"
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(1, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("Hello, world!", result[1].text)
    assert.is_false(result[1].partial)
    
    -- Test metadata
    assert.is_true(metadata.all_tools_complete)
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
  end)

  it("should parse text with complete tool use", function()
    local text = 'Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt", "content": "foo"}}</tool_use>'
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    
    -- First part: text
    assert.are.equal("text", result[1].type)
    assert.are.equal("Hello, world! I am a tool.", result[1].text)
    assert.is_false(result[1].partial)
    
    -- Second part: tool use
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal("path/to/file.txt", result[2].tool_input.path)
    assert.are.equal("foo", result[2].tool_input.content)
    assert.is_false(result[2].partial)
    
    -- Test metadata
    assert.is_true(metadata.all_tools_complete)
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
  end)

  it("should parse text with partial tool use", function()
    local text = 'Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt"'
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    
    -- First part: text
    assert.are.equal("text", result[1].type)
    assert.are.equal("Hello, world! I am a tool.", result[1].text)
    assert.is_false(result[1].partial)
    
    -- Second part: partial tool use
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("write", result[2].tool_name)
    assert.are.equal("path/to/file.txt", result[2].tool_input.path)
    assert.is_true(result[2].partial)
    
    -- Test metadata
    assert.is_false(metadata.all_tools_complete)
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
  end)

  it("should parse text with multiple complete tools", function()
    local text = 'Hello, world! I am a tool.<tool_use>{"name": "write", "input": {"path": "path/to/file.txt", "content": "foo"}}</tool_use>I am another tool.<tool_use>{"name": "read", "input": {"path": "path/to/file2.txt"}}</tool_use>hello'
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(5, #result)
    
    -- Verify all parts
    assert.are.equal("text", result[1].type)
    assert.are.equal("tool_use", result[2].type)
    assert.are.equal("text", result[3].type)
    assert.are.equal("tool_use", result[4].type)
    assert.are.equal("text", result[5].type)
    
    -- Verify tools are complete
    assert.is_false(result[2].partial)
    assert.is_false(result[4].partial)
    
    -- Test metadata
    assert.is_true(metadata.all_tools_complete)
    assert.are.equal(2, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
  end)

  it("should parse text with mix of complete and partial tools", function()
    local text = 'Text1<tool_use>{"name": "complete", "input": {"arg": "value"}}</tool_use>Text2<tool_use>{"name": "partial"'
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(4, #result)
    
    -- First tool should be complete
    assert.are.equal("tool_use", result[2].type)
    assert.is_false(result[2].partial)
    
    -- Second tool should be partial
    assert.are.equal("tool_use", result[4].type)
    assert.is_true(result[4].partial)
    
    -- Test metadata
    assert.is_false(metadata.all_tools_complete)
    assert.are.equal(2, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
  end)

  it("should handle empty input", function()
    local text = ""
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(0, #result)
    
    -- Test metadata
    assert.is_true(metadata.all_tools_complete)
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
  end)

  it("should handle malformed tool use", function()
    local text = 'Text<tool_use>invalid json</tool_use>More text'
    local result, metadata = ReActParser.parse(text)
    
    -- Should treat malformed tool use as text
    assert.are.equal(2, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("text", result[2].type)
    
    -- Test metadata
    assert.is_true(metadata.all_tools_complete)
    assert.are.equal(0, metadata.tool_count)
    assert.are.equal(0, metadata.partial_tool_count)
  end)

  it("should handle tool use without closing tag", function()
    local text = 'Text<tool_use>{"name": "test", "input": {}}' -- No closing tag
    local result, metadata = ReActParser.parse(text)
    
    assert.are.equal(2, #result)
    assert.are.equal("text", result[1].type)
    assert.are.equal("tool_use", result[2].type)
    assert.is_true(result[2].partial)
    
    -- Test metadata
    assert.is_false(metadata.all_tools_complete)
    assert.are.equal(1, metadata.tool_count)
    assert.are.equal(1, metadata.partial_tool_count)
  end)
end)
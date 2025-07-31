local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct Parser", function()
  describe("parse function", function()
    it("should parse text content without tools", function()
      local text = "Hello, world!"
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(1, #result)
      assert.are.equal("text", result[1].type)
      assert.are.equal("Hello, world!", result[1].text)
      assert.is_false(result[1].partial)
      
      assert.are.equal(0, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.are.equal(0, metadata.complete_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)

    it("should parse complete tool use", function()
      local text = 'Hello! <tool_use>{"name": "write", "input": {"path": "test.txt", "content": "foo"}}</tool_use>'
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, #result)
      assert.are.equal("text", result[1].type)
      assert.are.equal("Hello! ", result[1].text)
      
      assert.are.equal("tool_use", result[2].type)
      assert.are.equal("write", result[2].tool_name)
      assert.are.equal("test.txt", result[2].tool_input.path)
      assert.are.equal("foo", result[2].tool_input.content)
      assert.is_false(result[2].partial)
      
      assert.are.equal(1, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.are.equal(1, metadata.complete_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)

    it("should parse partial tool use", function()
      local text = 'Hello! <tool_use>{"name": "write", "input": {"path": "test.txt"'
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, #result)
      assert.are.equal("text", result[1].type)
      assert.are.equal("Hello! ", result[1].text)
      
      assert.are.equal("tool_use", result[2].type)
      assert.are.equal("write", result[2].tool_name)
      assert.are.equal("test.txt", result[2].tool_input.path)
      assert.is_true(result[2].partial)
      
      assert.are.equal(1, metadata.tool_count)
      assert.are.equal(1, metadata.partial_tool_count)
      assert.are.equal(0, metadata.complete_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)

    it("should parse multiple tools with mixed completion states", function()
      local text = 'First tool: <tool_use>{"name": "write", "input": {"path": "file1.txt", "content": "data1"}}</tool_use> Second tool: <tool_use>{"name": "read", "input": {"path": "file2.txt"'
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(4, #result)
      
      -- First tool complete
      assert.are.equal("tool_use", result[2].type)
      assert.are.equal("write", result[2].tool_name)
      assert.is_false(result[2].partial)
      
      -- Second tool partial
      assert.are.equal("tool_use", result[4].type)
      assert.are.equal("read", result[4].tool_name)
      assert.is_true(result[4].partial)
      
      assert.are.equal(2, metadata.tool_count)
      assert.are.equal(1, metadata.partial_tool_count)
      assert.are.equal(1, metadata.complete_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)

    it("should handle all complete tools correctly", function()
      local text = 'First: <tool_use>{"name": "write", "input": {"path": "file1.txt"}}</tool_use> Second: <tool_use>{"name": "read", "input": {"path": "file2.txt"}}</tool_use>'
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.are.equal(2, metadata.complete_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)

    it("should handle empty input correctly", function()
      local text = ""
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(0, #result)
      assert.are.equal(0, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.are.equal(0, metadata.complete_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)
  end)
end)
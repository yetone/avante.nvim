local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct_parser2", function()
  describe("parse with metadata", function()
    it("should return metadata for simple text", function()
      local result, metadata = ReActParser.parse("Hello, world!")
      assert.equals(1, #result)
      assert.equals("text", result[1].type)
      assert.equals("Hello, world!", result[1].text)
      assert.is_false(result[1].partial)
      
      assert.is_false(metadata.all_tools_complete)
      assert.equals(0, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
    end)

    it("should return metadata for complete tool", function()
      local text = 'I need to write a file.<tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use>'
      local result, metadata = ReActParser.parse(text)
      
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.equals("write", result[2].tool_name)
      assert.is_false(result[2].partial)
      
      assert.is_true(metadata.all_tools_complete)
      assert.equals(1, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
    end)

    it("should return metadata for partial tool", function()
      local text = 'I need to write a file.<tool_use>{"name": "write", "input": {"path": "test.txt"'
      local result, metadata = ReActParser.parse(text)
      
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.equals("write", result[2].tool_name)
      assert.is_true(result[2].partial)
      
      assert.is_false(metadata.all_tools_complete)
      assert.equals(1, metadata.tool_count)
      assert.equals(1, metadata.partial_tool_count)
    end)

    it("should return metadata for mixed complete and partial tools", function()
      local text = 'First tool:<tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use>Second tool:<tool_use>{"name": "read", "input": {"path"'
      local result, metadata = ReActParser.parse(text)
      
      assert.equals(4, #result)
      assert.equals("tool_use", result[2].type)
      assert.is_false(result[2].partial)
      assert.equals("tool_use", result[4].type)
      assert.is_true(result[4].partial)
      
      assert.is_false(metadata.all_tools_complete)
      assert.equals(2, metadata.tool_count)
      assert.equals(1, metadata.partial_tool_count)
    end)

    it("should return metadata for multiple complete tools", function()
      local text = 'First:<tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use>Second:<tool_use>{"name": "read", "input": {"path": "test.txt"}}</tool_use>'
      local result, metadata = ReActParser.parse(text)
      
      assert.equals(4, #result)
      assert.equals("tool_use", result[2].type)
      assert.is_false(result[2].partial)
      assert.equals("tool_use", result[4].type)
      assert.is_false(result[4].partial)
      
      assert.is_true(metadata.all_tools_complete)
      assert.equals(2, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
    end)
  end)
end)
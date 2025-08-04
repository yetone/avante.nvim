local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReActParser with metadata", function()
  describe("parse", function()
    it("should parse complete tools and return correct metadata", function()
      local input = [[Hello, world! I'll use a tool.
<tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use>
Done with tool.]]
      
      local result, metadata = ReActParser.parse(input)
      
      assert.equals(3, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.equals("write", result[2].tool_name)
      assert.is_false(result[2].partial)
      assert.equals("text", result[3].type)
      
      -- Check metadata
      assert.is_true(metadata.all_tools_complete)
      assert.equals(1, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
    end)

    it("should parse partial tools and return correct metadata", function()
      local input = [[I'll use a partial tool.
<tool_use>{"name": "write", "input": {"path": "test.txt"]]
      
      local result, metadata = ReActParser.parse(input)
      
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.equals("write", result[2].tool_name)
      assert.is_true(result[2].partial)
      
      -- Check metadata
      assert.is_false(metadata.all_tools_complete)
      assert.equals(1, metadata.tool_count)
      assert.equals(1, metadata.partial_tool_count)
    end)

    it("should handle mixed complete and partial tools", function()
      local input = [[First complete tool:
<tool_use>{"name": "write", "input": {"path": "test1.txt", "content": "hello"}}</tool_use>
Then partial tool:
<tool_use>{"name": "read", "input": {"path"]]
      
      local result, metadata = ReActParser.parse(input)
      
      assert.equals(4, #result)
      assert.equals("tool_use", result[2].type)
      assert.is_false(result[2].partial)  -- complete tool
      assert.equals("tool_use", result[4].type)
      assert.is_true(result[4].partial)   -- partial tool
      
      -- Check metadata
      assert.is_false(metadata.all_tools_complete)
      assert.equals(2, metadata.tool_count)
      assert.equals(1, metadata.partial_tool_count)
    end)

    it("should handle text-only input", function()
      local input = "Just plain text with no tools."
      
      local result, metadata = ReActParser.parse(input)
      
      assert.equals(1, #result)
      assert.equals("text", result[1].type)
      
      -- Check metadata
      assert.is_true(metadata.all_tools_complete)
      assert.equals(0, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
    end)

    it("should handle empty input", function()
      local input = ""
      
      local result, metadata = ReActParser.parse(input)
      
      assert.equals(0, #result)
      
      -- Check metadata
      assert.is_true(metadata.all_tools_complete)
      assert.equals(0, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
    end)
  end)
end)
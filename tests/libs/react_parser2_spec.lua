local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReActParser2", function()
  describe("parse", function()
    it("returns metadata about tool completion", function()
      local text = [[Hello world!]]
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(1, #result)
      assert.are.same({
        all_tools_complete = false,
        tool_count = 0,
        partial_tool_count = 0,
      }, metadata)
    end)
    
    it("tracks complete tools in metadata", function()
      local text = [[Hello<tool_use>{"name": "write", "input": {"path": "file.txt", "content": "foo"}}</tool_use>world!]]
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(3, #result)
      assert.are.same({
        all_tools_complete = true,
        tool_count = 1,
        partial_tool_count = 0,
      }, metadata)
    end)
    
    it("tracks partial tools in metadata", function()
      local text = [[Hello<tool_use>{"name": "write", "input": {"path": "file.txt"]]
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, #result)
      assert.are.same({
        all_tools_complete = false,
        tool_count = 1,
        partial_tool_count = 1,
      }, metadata)
    end)
    
    it("tracks mixed complete and partial tools", function()
      local text = [[<tool_use>{"name": "write", "input": {"path": "file.txt", "content": "foo"}}</tool_use><tool_use>{"name": "read", "input": {"path"]]
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, #result)
      assert.are.same({
        all_tools_complete = false,
        tool_count = 2,
        partial_tool_count = 1,
      }, metadata)
    end)
    
    it("handles multiple complete tools", function()
      local text = [[<tool_use>{"name": "write", "input": {"path": "file1.txt", "content": "foo"}}</tool_use><tool_use>{"name": "write", "input": {"path": "file2.txt", "content": "bar"}}</tool_use>]]
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, #result)
      assert.are.same({
        all_tools_complete = true,
        tool_count = 2,
        partial_tool_count = 0,
      }, metadata)
    end)
    
    it("handles edge case with no tools but text content", function()
      local text = [[This is just text content with no tools.]]
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(1, #result)
      assert.are.equal("text", result[1].type)
      assert.are.same({
        all_tools_complete = false,
        tool_count = 0,
        partial_tool_count = 0,
      }, metadata)
    end)
    
    it("handles empty content", function()
      local text = ""
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(0, #result)
      assert.are.same({
        all_tools_complete = false,
        tool_count = 0,
        partial_tool_count = 0,
      }, metadata)
    end)
  end)
end)
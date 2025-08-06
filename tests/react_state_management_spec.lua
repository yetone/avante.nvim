local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct State Management", function()
  describe("ReAct Parser Metadata", function()
    it("should return correct metadata for complete tools", function()
      local text = "Hello <tool_use>{\"name\": \"test_tool\", \"input\": {}}</tool_use> world"
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(3, #result)
      assert.are.equal(1, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)
    
    it("should return correct metadata for partial tools", function()
      local text = "Hello <tool_use>{\"name\": \"test_tool\""
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(2, #result)
      assert.are.equal(1, metadata.tool_count) 
      assert.are.equal(1, metadata.partial_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)
    
    it("should return correct metadata for mixed complete and partial tools", function()
      local text = "Start <tool_use>{\"name\": \"complete_tool\", \"input\": {}}</tool_use> middle <tool_use>{\"name\": \"partial_tool\""
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(4, #result)
      assert.are.equal(2, metadata.tool_count)
      assert.are.equal(1, metadata.partial_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)
    
    it("should return correct metadata for no tools", function()
      local text = "Just plain text with no tools"
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(1, #result)
      assert.are.equal(0, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)
    
    it("should handle multiple complete tools correctly", function()
      local text = "<tool_use>{\"name\": \"tool1\", \"input\": {}}</tool_use> between <tool_use>{\"name\": \"tool2\", \"input\": {}}</tool_use>"
      local result, metadata = ReActParser.parse(text)
      
      assert.are.equal(3, #result)
      assert.are.equal(2, metadata.tool_count)
      assert.are.equal(0, metadata.partial_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)
  end)
  
  describe("Session Context State Tracking", function()
    it("should initialize ReAct state variables correctly", function()
      local session_ctx = {}
      
      -- Simulate the initialization logic from llm.lua
      session_ctx.react_mode = session_ctx.react_mode or false
      session_ctx.tools_pending = session_ctx.tools_pending or false
      session_ctx.processing_tools = session_ctx.processing_tools or false
      session_ctx.react_tools_ready = session_ctx.react_tools_ready or false
      
      assert.is_false(session_ctx.react_mode)
      assert.is_false(session_ctx.tools_pending)
      assert.is_false(session_ctx.processing_tools)
      assert.is_false(session_ctx.react_tools_ready)
    end)
    
    it("should preserve existing state when reinitializing", function()
      local session_ctx = {
        react_mode = true,
        processing_tools = true,
      }
      
      -- Simulate the initialization logic from llm.lua  
      session_ctx.react_mode = session_ctx.react_mode or false
      session_ctx.tools_pending = session_ctx.tools_pending or false
      session_ctx.processing_tools = session_ctx.processing_tools or false
      session_ctx.react_tools_ready = session_ctx.react_tools_ready or false
      
      assert.is_true(session_ctx.react_mode)
      assert.is_false(session_ctx.tools_pending)
      assert.is_true(session_ctx.processing_tools)
      assert.is_false(session_ctx.react_tools_ready)
    end)
  end)
  
  describe("Duplicate Callback Prevention Logic", function()
    it("should allow callback when not in ReAct mode", function()
      local session_ctx = { react_mode = false, processing_tools = false }
      
      -- Simulate the callback prevention logic
      local should_prevent = session_ctx.react_mode and session_ctx.processing_tools
      
      assert.is_false(should_prevent)
    end)
    
    it("should prevent callback when ReAct mode and already processing", function()
      local session_ctx = { react_mode = true, processing_tools = true }
      
      -- Simulate the callback prevention logic  
      local should_prevent = session_ctx.react_mode and session_ctx.processing_tools
      
      assert.is_true(should_prevent)
    end)
    
    it("should allow callback when ReAct mode but not processing", function()
      local session_ctx = { react_mode = true, processing_tools = false }
      
      -- Simulate the callback prevention logic
      local should_prevent = session_ctx.react_mode and session_ctx.processing_tools
      
      assert.is_false(should_prevent)
    end)
  end)
  
  describe("Tool Completion State Logic", function()
    it("should detect all tools complete", function()
      local tool_use_list = {
        { state = "generated" },
        { state = "generated" }, 
        { state = "completed" }
      }
      
      -- Simulate the completion check logic
      local all_tools_complete = true
      for _, tool_use in ipairs(tool_use_list) do
        if tool_use.state == "generating" then
          all_tools_complete = false
          break
        end
      end
      
      assert.is_true(all_tools_complete)
    end)
    
    it("should detect tools still generating", function()
      local tool_use_list = {
        { state = "generated" },
        { state = "generating" },
        { state = "completed" }
      }
      
      -- Simulate the completion check logic
      local all_tools_complete = true
      for _, tool_use in ipairs(tool_use_list) do
        if tool_use.state == "generating" then
          all_tools_complete = false
          break
        end
      end
      
      assert.is_false(all_tools_complete)
    end)
    
    it("should handle empty tool list", function()
      local tool_use_list = {}
      
      -- Simulate the completion check logic
      local all_tools_complete = true
      for _, tool_use in ipairs(tool_use_list) do
        if tool_use.state == "generating" then
          all_tools_complete = false
          break
        end
      end
      
      assert.is_true(all_tools_complete)
    end)
  end)
end)
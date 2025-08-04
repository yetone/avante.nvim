local LLM = require("avante.llm")
local ReActParser = require("avante.libs.ReAct_parser2")

describe("ReAct state management", function()
  before_each(function()
    -- Reset state before each test
    LLM._cleanup_react_state()
  end)

  after_each(function()
    -- Clean up after each test
    LLM._cleanup_react_state()
  end)

  describe("ReAct state initialization", function()
    it("should initialize ReAct mode when use_ReAct_prompt is true", function()
      local provider_conf = { use_ReAct_prompt = true, model = "gpt-4" }
      LLM._init_react_state(provider_conf)
      
      assert.is_true(LLM._react_state.react_mode)
      assert.is_false(LLM._react_state.tools_pending)
      assert.is_false(LLM._react_state.processing_tools)
      assert.is_false(LLM._react_state.react_tools_ready)
    end)

    it("should not initialize ReAct mode when use_ReAct_prompt is false", function()
      local provider_conf = { use_ReAct_prompt = false, model = "gpt-4" }
      LLM._init_react_state(provider_conf)
      
      assert.is_false(LLM._react_state.react_mode)
      assert.is_false(LLM._react_state.tools_pending)
      assert.is_false(LLM._react_state.processing_tools)
      assert.is_false(LLM._react_state.react_tools_ready)
    end)

    it("should not initialize ReAct mode when provider_conf is nil", function()
      LLM._init_react_state(nil)
      
      assert.is_false(LLM._react_state.react_mode)
      assert.is_false(LLM._react_state.tools_pending)
      assert.is_false(LLM._react_state.processing_tools)
      assert.is_false(LLM._react_state.react_tools_ready)
    end)
  end)

  describe("duplicate callback prevention", function()
    it("should prevent duplicate callbacks when in ReAct mode and processing tools", function()
      local provider_conf = { use_ReAct_prompt = true, model = "gpt-4" }
      LLM._init_react_state(provider_conf)
      LLM._react_state.processing_tools = true
      
      assert.is_true(LLM._should_prevent_duplicate_callback())
    end)

    it("should not prevent callbacks when not in ReAct mode", function()
      local provider_conf = { use_ReAct_prompt = false, model = "gpt-4" }
      LLM._init_react_state(provider_conf)
      LLM._react_state.processing_tools = true
      
      assert.is_false(LLM._should_prevent_duplicate_callback())
    end)

    it("should not prevent callbacks when in ReAct mode but not processing tools", function()
      local provider_conf = { use_ReAct_prompt = true, model = "gpt-4" }
      LLM._init_react_state(provider_conf)
      LLM._react_state.processing_tools = false
      
      assert.is_false(LLM._should_prevent_duplicate_callback())
    end)
  end)

  describe("state cleanup", function()
    it("should reset all state flags on cleanup", function()
      local provider_conf = { use_ReAct_prompt = true, model = "gpt-4" }
      LLM._init_react_state(provider_conf)
      LLM._react_state.processing_tools = true
      LLM._react_state.tools_pending = true
      LLM._react_state.react_tools_ready = true
      
      LLM._cleanup_react_state()
      
      assert.is_false(LLM._react_state.react_mode)
      assert.is_false(LLM._react_state.tools_pending)
      assert.is_false(LLM._react_state.processing_tools)
      assert.is_false(LLM._react_state.react_tools_ready)
    end)
  end)
end)

describe("ReAct parser metadata", function()
  describe("parse_with_metadata", function()
    it("should return correct metadata for text-only content", function()
      local text = "Hello, world!"
      local result, metadata = ReActParser.parse_with_metadata(text)
      
      assert.equals(1, #result)
      assert.equals("text", result[1].type)
      assert.equals(0, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)

    it("should return correct metadata for complete tools", function()
      local text = 'Hello! <tool_use>{"name": "write", "input": {"path": "test.txt", "content": "hello"}}</tool_use>'
      local result, metadata = ReActParser.parse_with_metadata(text)
      
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.is_false(result[2].partial)
      assert.equals(1, metadata.tool_count)
      assert.equals(0, metadata.partial_tool_count)
      assert.is_true(metadata.all_tools_complete)
    end)

    it("should return correct metadata for partial tools", function()
      local text = 'Hello! <tool_use>{"name": "write"'
      local result, metadata = ReActParser.parse_with_metadata(text)
      
      assert.equals(2, #result)
      assert.equals("text", result[1].type)
      assert.equals("tool_use", result[2].type)
      assert.is_true(result[2].partial)
      assert.equals(1, metadata.tool_count)
      assert.equals(1, metadata.partial_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)

    it("should return correct metadata for mixed complete and partial tools", function()
      local text = 'Hello! <tool_use>{"name": "write", "input": {"path": "test.txt"}}</tool_use> More text <tool_use>{"name": "read"'
      local result, metadata = ReActParser.parse_with_metadata(text)
      
      assert.equals(4, #result)
      assert.equals(2, metadata.tool_count)
      assert.equals(1, metadata.partial_tool_count)
      assert.is_false(metadata.all_tools_complete)
    end)
  end)
end)
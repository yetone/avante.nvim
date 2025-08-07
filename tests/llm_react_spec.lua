local LLM = require("avante.llm")

describe("LLM ReAct State Management", function()
  before_each(function()
    LLM._reset_react_state()
  end)
  
  it("should initialize ReAct state properly", function()
    assert.is_false(LLM._react_state.react_mode)
    assert.is_false(LLM._react_state.tools_pending)
    assert.is_false(LLM._react_state.processing_tools)
    assert.is_false(LLM._react_state.react_tools_ready)
  end)
  
  it("should set ReAct mode correctly", function()
    LLM._set_react_mode(true)
    assert.is_true(LLM._react_state.react_mode)
    
    LLM._set_react_mode(false)
    assert.is_false(LLM._react_state.react_mode)
  end)
  
  it("should track processing tools state", function()
    LLM._set_processing_tools(true)
    assert.is_true(LLM._react_state.processing_tools)
    
    LLM._set_processing_tools(false)
    assert.is_false(LLM._react_state.processing_tools)
  end)
  
  it("should track tools ready state", function()
    LLM._set_react_tools_ready(true)
    assert.is_true(LLM._react_state.react_tools_ready)
    
    LLM._set_react_tools_ready(false)
    assert.is_false(LLM._react_state.react_tools_ready)
  end)
  
  it("should reset state properly", function()
    -- Set some state
    LLM._set_react_mode(true)
    LLM._set_processing_tools(true)
    LLM._set_react_tools_ready(true)
    LLM._react_state.tools_pending = true
    
    -- Reset
    LLM._reset_react_state()
    
    -- Check all state is reset
    assert.is_false(LLM._react_state.react_mode)
    assert.is_false(LLM._react_state.tools_pending)
    assert.is_false(LLM._react_state.processing_tools)
    assert.is_false(LLM._react_state.react_tools_ready)
  end)
end)
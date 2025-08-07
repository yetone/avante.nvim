local LLM = require("avante.llm")

describe("ReAct State Management", function()
  local test_session_id = "test_session_123"
  
  before_each(function()
    -- Reset state before each test
    LLM.reset_react_state(test_session_id)
  end)
  
  describe("reset_react_state", function()
    it("resets all ReAct state variables", function()
      -- Set some state first
      LLM.set_react_mode(true, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      
      -- Reset should clear everything
      LLM.reset_react_state(test_session_id)
      
      assert.is_false(LLM.is_react_processing(test_session_id))
    end)
    
    it("handles nil session_id", function()
      assert.has_no.errors(function()
        LLM.reset_react_state(nil)
      end)
    end)
  end)
  
  describe("set_react_mode", function()
    it("sets ReAct mode for session", function()
      LLM.set_react_mode(true, test_session_id)
      -- We can't directly test the internal state, but we can test that processing works
      LLM.set_react_processing(true, test_session_id)
      assert.is_true(LLM.is_react_processing(test_session_id))
    end)
    
    it("handles session isolation", function()
      local other_session = "other_session_456"
      
      LLM.set_react_mode(true, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      
      -- Different session should not be affected
      assert.is_false(LLM.is_react_processing(other_session))
    end)
  end)
  
  describe("is_react_processing", function()
    it("returns false when not processing", function()
      LLM.set_react_mode(true, test_session_id)
      assert.is_false(LLM.is_react_processing(test_session_id))
    end)
    
    it("returns true when processing in ReAct mode", function()
      LLM.set_react_mode(true, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      assert.is_true(LLM.is_react_processing(test_session_id))
    end)
    
    it("returns false when processing but not in ReAct mode", function()
      LLM.set_react_mode(false, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      assert.is_false(LLM.is_react_processing(test_session_id))
    end)
    
    it("returns false for wrong session", function()
      local other_session = "other_session_456"
      
      LLM.set_react_mode(true, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      
      assert.is_false(LLM.is_react_processing(other_session))
    end)
    
    it("handles nil session_id", function()
      LLM.set_react_mode(true, nil)
      LLM.set_react_processing(true, nil)
      
      assert.is_true(LLM.is_react_processing(nil))
      assert.is_false(LLM.is_react_processing(test_session_id))
    end)
  end)
  
  describe("set_react_processing", function()
    it("sets processing state when in ReAct mode", function()
      LLM.set_react_mode(true, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      
      assert.is_true(LLM.is_react_processing(test_session_id))
      
      LLM.set_react_processing(false, test_session_id)
      assert.is_false(LLM.is_react_processing(test_session_id))
    end)
    
    it("ignores wrong session", function()
      local other_session = "other_session_456"
      
      LLM.set_react_mode(true, test_session_id)
      LLM.set_react_processing(true, test_session_id)
      
      -- Try to modify from different session - should be ignored
      LLM.set_react_processing(false, other_session)
      
      -- Original session should still be processing
      assert.is_true(LLM.is_react_processing(test_session_id))
    end)
  end)
  
  describe("session isolation", function()
    it("maintains separate state per session", function()
      local session_a = "session_a"
      local session_b = "session_b"
      
      -- Set up session A
      LLM.reset_react_state(session_a)
      LLM.set_react_mode(true, session_a)
      LLM.set_react_processing(true, session_a)
      
      -- Set up session B
      LLM.reset_react_state(session_b)
      LLM.set_react_mode(true, session_b)
      LLM.set_react_processing(false, session_b)
      
      -- Each session should maintain its own state
      assert.is_true(LLM.is_react_processing(session_a))
      assert.is_false(LLM.is_react_processing(session_b))
    end)
  end)
end)
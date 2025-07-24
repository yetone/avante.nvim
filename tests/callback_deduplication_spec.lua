describe("Callback Deduplication System", function()
  local Utils = require("avante.utils")
  
  -- Mock the required modules
  local mock_config = { debug = true }
  local callback_states = {}
  
  -- Helper function to simulate debug callback
  local function debug_callback(message, data)
    if mock_config.debug then
      print("[CALLBACK_DEBUG] " .. message .. " " .. vim.inspect(data or {}))
    end
  end
  
  -- Mock safe callback wrapper function
  local function safe_on_stop(completion_id, stop_opts, original_on_stop)
    local state = callback_states[completion_id]
    if not state then
      error("Missing callback state for completion: " .. completion_id)
    end
    
    debug_callback("Callback triggered", {
      completion_id = completion_id,
      reason = stop_opts.reason,
      streaming_tool_use = stop_opts.streaming_tool_use,
      callback_sent = state.callback_sent,
      last_reason = state.last_callback_reason,
    })
    
    -- Prevent duplicate callbacks with same reason for identical completion cycles
    if stop_opts.reason == "tool_use" and state.callback_sent and state.last_callback_reason == "tool_use" then
      debug_callback("Blocked duplicate tool_use callback", { completion_id = completion_id })
      return false
    end
    
    -- Update state
    state.callback_triggered = true
    state.last_callback_reason = stop_opts.reason
    if stop_opts.reason == "tool_use" then
      state.callback_sent = true
    end
    
    debug_callback("Executing callback", {
      completion_id = completion_id,
      reason = stop_opts.reason,
    })
    
    return true
  end
  
  before_each(function()
    callback_states = {}
  end)
  
  it("should initialize callback state correctly", function()
    local completion_id = "test_completion_1"
    callback_states[completion_id] = {
      completion_id = completion_id,
      tool_use_detected = false,
      callback_triggered = false,
      streaming_active = false,
      tool_processing_phase = "none",
      callback_sent = false,
      last_callback_reason = nil,
    }
    
    local state = callback_states[completion_id]
    assert.is_not_nil(state)
    assert.are.equal(completion_id, state.completion_id)
    assert.are.equal(false, state.callback_sent)
    assert.are.equal("none", state.tool_processing_phase)
  end)
  
  it("should allow first tool_use callback", function() 
    local completion_id = "test_completion_2"
    callback_states[completion_id] = {
      completion_id = completion_id,
      tool_use_detected = false,
      callback_triggered = false,
      streaming_active = false,
      tool_processing_phase = "none",
      callback_sent = false,
      last_callback_reason = nil,
    }
    
    local result = safe_on_stop(completion_id, { reason = "tool_use", streaming_tool_use = true }, function() end)
    
    assert.is_true(result)
    assert.is_true(callback_states[completion_id].callback_sent)
    assert.are.equal("tool_use", callback_states[completion_id].last_callback_reason)
  end)
  
  it("should block duplicate tool_use callbacks", function()
    local completion_id = "test_completion_3"
    callback_states[completion_id] = {
      completion_id = completion_id,
      tool_use_detected = false,
      callback_triggered = true,
      streaming_active = false,
      tool_processing_phase = "none",
      callback_sent = true,
      last_callback_reason = "tool_use",
    }
    
    local result = safe_on_stop(completion_id, { reason = "tool_use", streaming_tool_use = true }, function() end)
    
    assert.is_false(result)
  end)
  
  it("should allow complete callbacks after tool_use", function()
    local completion_id = "test_completion_4"
    callback_states[completion_id] = {
      completion_id = completion_id,
      tool_use_detected = false,
      callback_triggered = true,
      streaming_active = false,
      tool_processing_phase = "none",
      callback_sent = true,
      last_callback_reason = "tool_use",
    }
    
    local result = safe_on_stop(completion_id, { reason = "complete" }, function() end)
    
    assert.is_true(result)
    assert.are.equal("complete", callback_states[completion_id].last_callback_reason)
  end)
end)
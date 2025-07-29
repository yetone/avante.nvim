# ReAct Prompts Debugging Guide

This document provides debugging information for the ReAct prompts duplicate LLM API calls fix.

## Problem Overview

When `use_ReAct_prompt = true`, the system was making duplicate LLM API calls after tool completion. The issue occurred when providers called `on_stop({reason: 'tool_use'})` after the main handler had already processed tool completion, resulting in unnecessary API calls and increased costs.

## Root Cause

The duplicate calls were happening in two places:

1. **OpenAI Provider** (`lua/avante/providers/openai.lua:382-388`): When `[DONE]` was received with pending tools, it would call `on_stop({reason: 'tool_use'})` even if the main handler had already processed the tool completion.

2. **Gemini Provider** (`lua/avante/providers/gemini.lua:283-285`): When `STOP` was received with pending tools, it would call `on_stop({reason: 'tool_use'})` after the main handler had already processed completion.

## Solution Implementation

### 1. Tool Completion State Tracking

Added `tool_completion_tracker` in `lua/avante/llm.lua:771-775`:

```lua
local tool_completion_tracker = {
  has_pending_tools = false,
  completion_in_progress = false, 
  final_callback_sent = false,
}
```

### 2. Debug Logging

Enhanced debug logging in `llm.lua:787-794` to track:
- Callback reason
- Tool completion state
- ReAct mode status
- State transitions

### 3. Duplicate Prevention Logic

Both OpenAI and Gemini providers now check state before making duplicate calls:

```lua
if provider_conf.use_ReAct_prompt and opts.tool_completion_tracker then
  if opts.tool_completion_tracker.final_callback_sent then
    Utils.debug("Provider: Blocked duplicate tool_use callback after completion")
    return
  end
  if opts.tool_completion_tracker.completion_in_progress then
    Utils.debug("Provider: Blocked duplicate tool_use callback during processing")
    return
  end
end
```

## Debugging Configuration

### Enable Debug Logging

To monitor ReAct callback behavior, enable debug logging:

```lua
vim.g.avante_debug = true
```

Or set environment variable:
```bash
export AVANTE_DEBUG=1
```

### Debug Log Analysis

Look for these log patterns to identify duplicate callback issues:

1. **Normal Flow:**
```
[DEBUG] LLM on_stop callback: {reason: "tool_use", completion_in_progress: false, final_callback_sent: false}
[DEBUG] ReAct: Processing tool_use callback: {pending_tools_count: 1, completion_in_progress: true}
[DEBUG] ReAct: All tools completed, finalizing
```

2. **Blocked Duplicate:**
```
[DEBUG] OpenAI: Blocked duplicate tool_use callback after completion
[DEBUG] Gemini: Blocked duplicate tool_use callback during processing
```

### Common Debugging Steps

1. **Verify ReAct Mode:** Check that `use_ReAct_prompt = true` in provider config
2. **Monitor API Calls:** Count actual HTTP requests vs expected requests
3. **Check State Transitions:** Verify proper state management in logs
4. **Test Tool Sequences:** Test single tools, multiple tools, and mixed scenarios

### Performance Monitoring

The fix should result in:
- 50% reduction in duplicate API calls for ReAct workflows
- No performance regression in normal (non-ReAct) mode  
- Consistent behavior across OpenAI and Gemini providers

### Error Scenarios

The implementation handles these edge cases:
- Streaming interruption during tool execution
- Malformed ReAct XML tags
- Tool execution failures
- Proper state cleanup in error scenarios

## Testing

### Unit Tests

Run the test suite:
```bash
make luatest
```

Key test files:
- `tests/llm_spec.lua` - Tool completion state tracking
- `tests/react_callbacks_spec.lua` - ReAct callback handling

### Manual Testing

1. **OpenAI with ReAct:**
```lua
local config = {
  provider = "openai",
  use_ReAct_prompt = true,
}
-- Execute tool workflows and verify no duplicate API calls in logs
```

2. **Gemini with ReAct:**
```lua
local config = {
  provider = "gemini", 
  use_ReAct_prompt = true,
}
-- Execute tool workflows and verify proper STOP/TOOL_CODE handling
```

## Troubleshooting

### Issue: Still seeing duplicate calls
- Check that provider config has `use_ReAct_prompt = true`
- Verify `tool_completion_tracker` is passed to provider
- Review debug logs for state transitions

### Issue: Tools not executing
- Ensure normal (non-ReAct) mode still works
- Check for proper error handling in tool execution
- Verify state reset between requests

### Issue: Performance regression
- Monitor API call frequency before/after fix
- Check for any blocking in non-ReAct workflows
- Verify provider-specific behavior is consistent

## Related Files

- `lua/avante/llm.lua` - Main state tracking and on_stop handling
- `lua/avante/providers/openai.lua` - OpenAI duplicate prevention  
- `lua/avante/providers/gemini.lua` - Gemini duplicate prevention
- `tests/llm_spec.lua` - Unit tests for state tracking
- `tests/react_callbacks_spec.lua` - Integration tests for ReAct callbacks